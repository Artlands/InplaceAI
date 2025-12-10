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

    let frame = selection.range.flatMap { boundsForRange($0, in: element) } ?? frameForElement(element)
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
    selectedRange providedRange: CFRange? = nil,
    originalText: String? = nil
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

    let currentValue = elementStringValue(element)
    let effectiveRange = sanitizedRange(
      providedRange ?? selectedTextRange(for: element),
      in: currentValue,
      originalText: originalText
    )
    let expectedValue = expectedElementValue(
      currentValue: currentValue,
      range: effectiveRange,
      replacement: text,
      originalText: originalText
    )

    // Ensure the same selection is focused before attempting replacement.
    ensureSelectionActive(for: element, range: effectiveRange, selectAllFallback: false)

    if setSelectedTextAttribute(on: element, text: text),
      replacementConfirmed(
        expectedValue: expectedValue,
        replacement: text,
        previousValue: currentValue,
        on: element
      )
    {
      return
    }

    if try replaceUsingSelectedRange(on: element, replacement: text, providedRange: effectiveRange),
      replacementConfirmed(
        expectedValue: expectedValue,
        replacement: text,
        previousValue: currentValue,
        on: element
      )
    {
      return
    }

    if let expectedValue,
      AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, expectedValue as CFTypeRef)
        == .success,
      replacementConfirmed(
        expectedValue: expectedValue,
        replacement: text,
        previousValue: currentValue,
        on: element
      )
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

  private func boundsForRange(_ range: CFRange, in element: AXUIElement) -> CGRect? {
    var mutableRange = range
    guard let rangeValue = AXValueCreate(.cfRange, &mutableRange) else { return nil }

    var value: AnyObject?
    let result = AXUIElementCopyParameterizedAttributeValue(
      element,
      kAXBoundsForRangeParameterizedAttribute as CFString,
      rangeValue,
      &value
    )

    guard result == .success,
      let rectValue = value,
      CFGetTypeID(rectValue) == AXValueGetTypeID(),
      AXValueGetType(rectValue as! AXValue) == .cgRect
    else {
      return nil
    }

    var rect = CGRect.zero
    AXValueGetValue(rectValue as! AXValue, .cgRect, &rect)
    return rect
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

  private func expectedElementValue(
    currentValue: String?,
    range: CFRange?,
    replacement: String,
    originalText: String?
  ) -> String? {
    guard let currentValue else { return nil }

    if let range,
      let swiftRange = Range(NSRange(location: range.location, length: range.length), in: currentValue)
    {
      var updated = currentValue
      updated.replaceSubrange(swiftRange, with: replacement)
      return updated
    }

    guard let originalText, originalText.isEmpty == false else {
      return nil
    }

    guard let firstMatch = currentValue.range(of: originalText) else {
      return nil
    }
    let lastMatch = currentValue.range(of: originalText, options: .backwards)
    guard firstMatch == lastMatch else {
      return nil  // Avoid ambiguous replacements when the text repeats.
    }

    var updated = currentValue
    updated.replaceSubrange(firstMatch, with: replacement)
    return updated
  }

  private func sanitizedRange(
    _ range: CFRange?,
    in currentValue: String?,
    originalText: String?
  ) -> CFRange? {
    guard let currentValue, let originalText, originalText.isEmpty == false else {
      return range
    }

    guard let range else {
      return uniqueRange(of: originalText, in: currentValue)
    }

    guard
      let swiftRange = Range(NSRange(location: range.location, length: range.length), in: currentValue),
      String(currentValue[swiftRange]) == originalText
    else {
      return uniqueRange(of: originalText, in: currentValue)
    }

    return range
  }

  private func uniqueRange(of substring: String, in text: String) -> CFRange? {
    var searchStart = text.startIndex
    var foundRange: Range<String.Index>?

    while searchStart < text.endIndex,
      let range = text.range(of: substring, range: searchStart..<text.endIndex)
    {
      if foundRange != nil {
        return nil  // Multiple matches; avoid guessing.
      }
      foundRange = range
      searchStart = range.upperBound
    }

    guard let foundRange else { return nil }
    let nsRange = NSRange(foundRange, in: text)
    return CFRange(location: nsRange.location, length: nsRange.length)
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

  private func replacementConfirmed(
    expectedValue: String?,
    replacement: String,
    previousValue: String?,
    on element: AXUIElement
  ) -> Bool {
    let attempts = [0, 80_000, 120_000]  // microseconds

    for delay in attempts {
      if delay > 0 {
        usleep(useconds_t(delay))
      }

      let currentValue = elementStringValue(element)
      if let expectedValue, let currentValue, currentValue == expectedValue {
        return true
      }

      if let selection = try? selectedTextAndRange(for: element),
        selection.text == replacement
      {
        return true
      }

      if let previousValue, let currentValue, previousValue != currentValue {
        return true
      }
    }

    return false
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
