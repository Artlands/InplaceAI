import AppKit
import SwiftUI

@MainActor
final class InlineSuggestionWindow {
  enum Action {
    case accept
    case dismiss
  }

  private var window: NSWindow?
  private var eventMonitors: [Any] = []
  private var lastAnchor: CGRect?
  private var lastConvertedAnchor: CGRect?
  private var lastOrigin: CGPoint?
  private var dragOrigin: CGPoint?
  private var actionHandler: ((Action) -> Void)?

  func present(
    suggestion: Suggestion,
    anchor: CGRect?,
    isProcessing: Bool,
    onAction: @escaping (Action) -> Void
  ) {
    actionHandler = onAction

    let contentView = SuggestionBubbleView(
      suggestion: suggestion,
      isProcessing: isProcessing,
      acceptAction: { [weak self] in self?.handle(action: .accept) },
      dismissAction: { [weak self] in self?.handle(action: .dismiss) },
      onDragChanged: { [weak self] translation in
        self?.handleDrag(translation: translation, ended: false)
      },
      onDragEnded: { [weak self] translation in
        self?.handleDrag(translation: translation, ended: true)
      }
    )

    let hostingView = NSHostingView(rootView: contentView)
    hostingView.translatesAutoresizingMaskIntoConstraints = false

    let window =
      window
      ?? NSWindow(
        contentRect: CGRect(origin: .zero, size: CGSize(width: 360, height: 180)),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
      )

    window.contentView = hostingView
    window.isReleasedWhenClosed = false
    window.backgroundColor = .clear
    window.isOpaque = false
    window.level = .statusBar
    window.collectionBehavior = [.canJoinAllSpaces, .transient]
    window.ignoresMouseEvents = false
    window.hasShadow = false
    window.isMovableByWindowBackground = true
    self.window = window

    hostingView.layoutSubtreeIfNeeded()
    window.setContentSize(hostingView.fittingSize)
    positionWindow(window, anchor: anchor)
    window.makeKeyAndOrderFront(nil)
    startMonitoringEvents()
  }

  func dismiss(notify: Bool = false) {
    window?.orderOut(nil)
    stopMonitoringEvents()
    lastAnchor = nil
    lastOrigin = nil
    if notify {
      actionHandler?(.dismiss)
    }
    actionHandler = nil
  }

  private func handle(action: Action) {
    actionHandler?(action)
  }

  private func positionWindow(_ window: NSWindow, anchor: CGRect?) {
    let anchorRect = anchor ?? lastAnchor
    let screen = anchorRect.flatMap(screenForAXRect) ?? window.screen ?? NSScreen.main
    let convertedAnchor = anchorRect.map { convertAXRectToCocoa($0, on: screen) } ?? lastConvertedAnchor
    let target = convertedAnchor.map { CGPoint(x: $0.midX, y: $0.maxY) } ?? NSEvent.mouseLocation

    let size = window.frame.size
    var origin = lastOrigin ?? CGPoint(x: target.x - size.width / 2, y: target.y + 10)

    if let anchorRect,
      let previous = lastAnchor,
      previous != anchorRect
    {
      // Anchor changed due to a new selection; snap back near the new text.
      origin = CGPoint(x: target.x - size.width / 2, y: target.y + 10)
    } else if anchorRect != nil, lastAnchor == nil {
      origin = CGPoint(x: target.x - size.width / 2, y: target.y + 10)
    }

    origin = clampedOrigin(origin, windowSize: size, target: target, screen: screen)

    window.setFrame(CGRect(origin: origin, size: size), display: true)
    lastAnchor = anchorRect ?? lastAnchor
    lastConvertedAnchor = convertedAnchor ?? lastConvertedAnchor
    lastOrigin = origin
    dragOrigin = nil
  }

  private func startMonitoringEvents() {
    stopMonitoringEvents()
    if let mouseMonitor = NSEvent.addGlobalMonitorForEvents(
      matching: [.leftMouseDown, .rightMouseDown],
      handler: { [weak self] event in
        guard let self, let window else { return }
        // Only dismiss when clicking outside the bubble.
        if window.frame.contains(event.locationInWindow) { return }
        dismiss(notify: true)
      }
    ) {
      eventMonitors.append(mouseMonitor)
    }

    if let keyMonitor = NSEvent.addLocalMonitorForEvents(
      matching: [.keyDown],
      handler: { [weak self] event in
        guard let self else { return event }
        if event.keyCode == 53 {  // Escape
          dismiss(notify: true)
          return nil
        }
        return event
      }
    ) {
      eventMonitors.append(keyMonitor)
    }
  }

  private func stopMonitoringEvents() {
    for monitor in eventMonitors {
      NSEvent.removeMonitor(monitor)
    }
    eventMonitors.removeAll()
  }

  private func handleDrag(translation: CGSize, ended: Bool) {
    guard let window else { return }
    let startOrigin = dragOrigin ?? window.frame.origin
    let newOrigin = CGPoint(
      x: startOrigin.x + translation.width,
      y: startOrigin.y - translation.height  // Cocoa's Y axis is flipped from SwiftUI's drag.
    )
    let clamped = clampedOrigin(newOrigin, windowSize: window.frame.size, target: nil, screen: window.screen)
    window.setFrame(CGRect(origin: clamped, size: window.frame.size), display: true)

    if ended {
      lastOrigin = clamped
      dragOrigin = nil
    } else {
      dragOrigin = startOrigin
    }
  }

  private func clampedOrigin(
    _ origin: CGPoint,
    windowSize: CGSize,
    target: CGPoint?,
    screen: NSScreen?
  ) -> CGPoint {
    guard let screen else { return origin }
    var adjusted = origin
    let screenFrame = screen.visibleFrame

    if adjusted.x + windowSize.width > screenFrame.maxX {
      adjusted.x = screenFrame.maxX - windowSize.width - 8
    }
    if adjusted.x < screenFrame.minX {
      adjusted.x = screenFrame.minX + 8
    }
    if adjusted.y + windowSize.height > screenFrame.maxY {
      if let target {
        adjusted.y = target.y - windowSize.height - 12
      } else {
        adjusted.y = screenFrame.maxY - windowSize.height - 8
      }
    }
    if adjusted.y < screenFrame.minY {
      adjusted.y = screenFrame.minY + 8
    }
    return adjusted
  }

  private func screenForAXRect(_ rect: CGRect) -> NSScreen? {
    let center = CGPoint(x: rect.midX, y: rect.midY)
    return NSScreen.screens.first { $0.frame.contains(center) }
  }

  private func convertAXRectToCocoa(_ rect: CGRect, on screen: NSScreen?) -> CGRect {
    guard let screen else { return rect }
    let flippedY = screen.frame.origin.y + screen.frame.height - rect.origin.y - rect.height
    return CGRect(x: rect.origin.x, y: flippedY, width: rect.width, height: rect.height)
  }
}
