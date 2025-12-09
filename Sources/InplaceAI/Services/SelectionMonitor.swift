import AppKit
import ApplicationServices
import Foundation

@MainActor
final class SelectionMonitor {
  private let systemWideElement = AXUIElementCreateSystemWide()

  func captureSelection() throws -> TextSelection {
    guard AccessibilityAuthorizer.isTrusted else {
      throw SelectionError.accessibilityDenied
    }

    let element = try focusedElement()
    var selection = try selectedTextAndRange(for: element)

    if selection == nil {
      selection = try captureSelectionViaClipboard(focusedElement: element)
    }

    guard let selection else {
      throw SelectionError.unsupportedElement
    }

    if selection.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      throw SelectionError.emptySelection
    }

    let frame = frameForElement(element)
    return TextSelection(
      text: selection.text,
      frame: frame,
      element: element,
      selectedRange: selection.range
    )
  }

  func replaceSelection(
    with text: String,
    element providedElement: AXUIElement? = nil,
    selectedRange providedRange: CFRange? = nil
  ) throws {
    guard AccessibilityAuthorizer.isTrusted else {
      throw SelectionError.accessibilityDenied
    }

    let element: AXUIElement
    if let providedElement {
      element = providedElement
    } else {
      element = try focusedElement()
    }

    // Ensure the same selection is focused before attempting replacement.
    ensureSelectionActive(for: element, range: providedRange, selectAllFallback: false)

    if setSelectedTextAttribute(on: element, text: text),
      (try? selectedTextAndRange(for: element)?.text == text) == true
    {
      return
    }

    if try replaceUsingSelectedRange(
      on: element,
      replacement: text,
      providedRange: providedRange
    ),
      (try? selectedTextAndRange(for: element)?.text == text) == true
    {
      return
    }

    throw SelectionError.unsupportedElement
  }

  private func focusedElement() throws -> AXUIElement {
    var focused: AnyObject?
    let result = AXUIElementCopyAttributeValue(
      systemWideElement,
      kAXFocusedUIElementAttribute as CFString,
      &focused
    )

    guard result == .success, let element = focused else {
      throw SelectionError.noFocusedElement
    }

    return element as! AXUIElement
  }

  private func selectedTextAndRange(for element: AXUIElement) throws -> (
    text: String, range: CFRange?
  )? {
    var value: AnyObject?
    let error = AXUIElementCopyAttributeValue(
      element,
      kAXSelectedTextAttribute as CFString,
      &value
    )

    if error == .success {
      if let text = value as? String {
        return (text, selectedTextRange(for: element))
      } else if let attributed = value as? NSAttributedString {
        return (attributed.string, selectedTextRange(for: element))
      }
    }

    if let range = selectedTextRange(for: element),
      let fullValue = elementStringValue(element),
      let swiftRange = Range(NSRange(location: range.location, length: range.length), in: fullValue)
    {
      if range.length == 0 {
        throw SelectionError.emptySelection
      }
      return (String(fullValue[swiftRange]), range)
    }

    return nil
  }

  private func frameForElement(_ element: AXUIElement) -> CGRect? {
    var positionValue: AnyObject?
    var sizeValue: AnyObject?

    var result = AXUIElementCopyAttributeValue(
      element,
      kAXPositionAttribute as CFString,
      &positionValue
    )

    guard result == .success,
      let positionCF = positionValue,
      CFGetTypeID(positionCF) == AXValueGetTypeID()
    else {
      return nil
    }

    result = AXUIElementCopyAttributeValue(
      element,
      kAXSizeAttribute as CFString,
      &sizeValue
    )

    guard result == .success,
      let sizeCF = sizeValue,
      CFGetTypeID(sizeCF) == AXValueGetTypeID()
    else {
      return nil
    }

    var origin = CGPoint.zero
    var size = CGSize.zero
    AXValueGetValue(positionCF as! AXValue, .cgPoint, &origin)
    AXValueGetValue(sizeCF as! AXValue, .cgSize, &size)
    return CGRect(origin: origin, size: size)
  }

  @discardableResult
  func ensureSelectionActive(
    for element: AXUIElement?,
    range: CFRange?,
    selectAllFallback: Bool
  ) -> Bool {
    guard let element else { return false }
    activateApplication(for: element)

    if let range {
      var mutableRange = range
      if let axRange = AXValueCreate(.cfRange, &mutableRange) {
        let result = AXUIElementSetAttributeValue(
          element,
          kAXSelectedTextRangeAttribute as CFString,
          axRange
        )
        if result == .success {
          return true
        }
      }
    }

    if selectAllFallback {
      CGSynthesizeCommandA()
      return true
    }

    return false
  }

  private func captureSelectionViaClipboard(focusedElement: AXUIElement) throws -> (
    text: String, range: CFRange?
  )? {
    let pasteboard = NSPasteboard.general
    let existingItems = pasteboard.pasteboardItems?.compactMap { item -> NSPasteboardItem? in
      let copy = NSPasteboardItem()
      for type in item.types {
        if let data = item.data(forType: type) {
          copy.setData(data, forType: type)
        }
      }
      return copy
    }

    pasteboard.clearContents()
    CGSynthesizeCommandC()
    usleep(150_000)

    guard let copied = pasteboard.string(forType: .string) else {
      if let existingItems, !existingItems.isEmpty {
        pasteboard.clearContents()
        pasteboard.writeObjects(existingItems)
      }
      return nil
    }

    if let existingItems, !existingItems.isEmpty {
      pasteboard.clearContents()
      pasteboard.writeObjects(existingItems)
    }

    return (copied, selectedTextRange(for: focusedElement))
  }

  private func setSelectedTextAttribute(on element: AXUIElement, text: String) -> Bool {
    let error = AXUIElementSetAttributeValue(
      element,
      kAXSelectedTextAttribute as CFString,
      text as CFTypeRef
    )

    return error == .success
  }

  private func replaceUsingSelectedRange(
    on element: AXUIElement,
    replacement: String,
    providedRange: CFRange?
  ) throws -> Bool {
    let range = providedRange ?? selectedTextRange(for: element)

    guard let range else { return false }
    if range.length == 0 {
      throw SelectionError.emptySelection
    }

    guard
      let fullValue = elementStringValue(element),
      let swiftRange = Range(NSRange(location: range.location, length: range.length), in: fullValue)
    else {
      return false
    }

    var updated = fullValue
    updated.replaceSubrange(swiftRange, with: replacement)

    let error = AXUIElementSetAttributeValue(
      element,
      kAXValueAttribute as CFString,
      updated as CFTypeRef
    )

    return error == .success
  }


  private func selectedTextRange(for element: AXUIElement) -> CFRange? {
    var value: AnyObject?
    let result = AXUIElementCopyAttributeValue(
      element,
      kAXSelectedTextRangeAttribute as CFString,
      &value
    )

    guard result == .success,
      let rangeValue = value,
      CFGetTypeID(rangeValue) == AXValueGetTypeID(),
      AXValueGetType(rangeValue as! AXValue) == .cfRange
    else {
      return nil
    }

    var range = CFRange()
    AXValueGetValue(rangeValue as! AXValue, .cfRange, &range)
    return range
  }

  private func elementStringValue(_ element: AXUIElement) -> String? {
    var value: AnyObject?
    let error = AXUIElementCopyAttributeValue(
      element,
      kAXValueAttribute as CFString,
      &value
    )

    guard error == .success else { return nil }
    if let text = value as? String {
      return text
    } else if let attributed = value as? NSAttributedString {
      return attributed.string
    }
    return nil
  }

  private func activateApplication(for element: AXUIElement) {
    var pid: pid_t = 0
    let pidResult = AXUIElementGetPid(element, &pid)
    guard pidResult == .success else { return }

    if let app = NSRunningApplication(processIdentifier: pid) {
      app.activate(options: [.activateIgnoringOtherApps])
    }
  }
}
