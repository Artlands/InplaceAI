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
  private var lastOrigin: CGPoint?
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
      dismissAction: { [weak self] in self?.handle(action: .dismiss) }
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
    var target = NSEvent.mouseLocation
    if let anchorRect {
      target = CGPoint(x: anchorRect.minX + 4, y: anchorRect.maxY + 2)
    }

    let size = window.frame.size
    var origin = lastOrigin ?? CGPoint(x: target.x, y: target.y)
    if let anchorRect,
      let previous = lastAnchor,
      previous != anchorRect
    {
      // Recompute origin on anchor change to avoid jumps; otherwise preserve.
      origin = CGPoint(x: anchorRect.minX + 4, y: anchorRect.maxY + 2)
    } else if let anchorRect, lastAnchor == nil {
      origin = CGPoint(x: anchorRect.minX + 4, y: anchorRect.maxY + 2)
    }

    // Keep the bubble on-screen.
    if let screen = NSScreen.main {
      let screenFrame = screen.visibleFrame
      if origin.x + size.width > screenFrame.maxX {
        origin.x = screenFrame.maxX - size.width - 8
      }
      if origin.x < screenFrame.minX {
        origin.x = screenFrame.minX + 8
      }
      if origin.y + size.height > screenFrame.maxY {
        origin.y = target.y - size.height - 8
      }
      if origin.y < screenFrame.minY {
        origin.y = screenFrame.minY + 8
      }
    }

    window.setFrame(CGRect(origin: origin, size: size), display: true)
    lastAnchor = anchorRect ?? lastAnchor
    lastOrigin = origin
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
}
