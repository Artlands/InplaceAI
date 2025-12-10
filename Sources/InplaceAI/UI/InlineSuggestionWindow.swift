import AppKit
import SwiftUI

// Borderless panel that can become key so the inline editor accepts keyboard input.
private final class InlineSuggestionPanel: NSPanel {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }
}

@MainActor
final class InlineSuggestionWindow {
  enum Action {
    case accept(String)
    case dismiss
  }

  private let maxBubbleWidth: CGFloat = 520
  private var window: InlineSuggestionPanel?
  private var eventMonitors: [Any] = []
  private var lastAnchor: CGRect?
  private var lastConvertedAnchor: CGRect?
  private var lastOrigin: CGPoint?
  private var dragStartWindowOrigin: CGPoint?
  private var dragStartMouseLocation: CGPoint?
  private var dragRecognizer: NSPanGestureRecognizer?
  private var isDragging = false
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
      acceptAction: { [weak self] text in self?.handle(action: .accept(text)) },
      dismissAction: { [weak self] in self?.handle(action: .dismiss) }
    )

    let hostingView = NSHostingView(rootView: contentView)
    hostingView.translatesAutoresizingMaskIntoConstraints = false

    let window =
      window
      ?? InlineSuggestionPanel(
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
    window.animationBehavior = .none
    window.ignoresMouseEvents = false
    window.hasShadow = false
    // We handle dragging manually to avoid AppKit's built-in move logic fighting our gesture and causing flicker.
    window.isMovableByWindowBackground = false
    self.window = window

    let availableWidth = (window.screen ?? NSScreen.main)?.visibleFrame.width ?? maxBubbleWidth
    let widthLimit = max(280, min(maxBubbleWidth, availableWidth - 32))
    hostingView.widthAnchor.constraint(lessThanOrEqualToConstant: widthLimit).isActive = true
    hostingView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    attachDragRecognizer(to: hostingView, window: window)
    hostingView.layoutSubtreeIfNeeded()
    window.setContentSize(hostingView.fittingSize)
    positionWindow(window, anchor: anchor)
    NSApp.activate(ignoringOtherApps: true)
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
    switch action {
    case .dismiss:
      dismiss(notify: true)
    case .accept:
      actionHandler?(action)
    }
  }

  private func positionWindow(_ window: NSWindow, anchor: CGRect?) {
    let anchorRect = anchor ?? lastAnchor
    if isDragging { return }
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
    dragStartMouseLocation = nil
    dragStartWindowOrigin = nil
  }

  private func startMonitoringEvents() {
    stopMonitoringEvents()
    if let mouseMonitor = NSEvent.addGlobalMonitorForEvents(
      matching: [.leftMouseDown, .rightMouseDown],
      handler: { [weak self] event in
        guard let self, let window, !isDragging else { return }
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

  private func attachDragRecognizer(to view: NSView, window: NSWindow) {
    if let existing = dragRecognizer {
      existing.view?.removeGestureRecognizer(existing)
    }

    let recognizer = NSPanGestureRecognizer(target: self, action: #selector(handleDragGesture(_:)))
    recognizer.delaysPrimaryMouseButtonEvents = false
    view.addGestureRecognizer(recognizer)
    dragRecognizer = recognizer
  }

  @objc private func handleDragGesture(_ gesture: NSPanGestureRecognizer) {
    guard let window else { return }

    switch gesture.state {
    case .began:
      isDragging = true
      dragStartWindowOrigin = window.frame.origin
      dragStartMouseLocation = NSEvent.mouseLocation
    case .changed:
      guard
        let startOrigin = dragStartWindowOrigin,
        let startMouse = dragStartMouseLocation
      else { return }

      let current = NSEvent.mouseLocation
      let delta = CGSize(width: current.x - startMouse.x, height: current.y - startMouse.y)
      let newOrigin = CGPoint(x: startOrigin.x + delta.width, y: startOrigin.y + delta.height)
      let clamped = clampedOrigin(newOrigin, windowSize: window.frame.size, target: nil, screen: window.screen)
      window.setFrameOrigin(clamped)
    case .ended, .cancelled, .failed:
      lastOrigin = window.frame.origin
      dragStartMouseLocation = nil
      dragStartWindowOrigin = nil
      isDragging = false
    default:
      break
    }
  }
}
