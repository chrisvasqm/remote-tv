import AppKit
import SwiftUI

/// Reports when the menu-bar panel is shown or hidden. onAppear/onDisappear are not
/// called reliably for MenuBarExtra windows, but the window's occlusion state is.
///
/// It also keeps the panel under the menu bar when its content shrinks: MenuBarExtra
/// keeps the window's bottom edge in place, which leaves a short panel hanging far below.
struct PanelVisibility: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = VisibilityView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class VisibilityView: NSView {
        var onChange: ((Bool) -> Void)?
        private var observers: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            guard let window else { return observers = [] }
            observers = [
                NotificationCenter.default.addObserver(
                    forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
                ) { [weak self, weak window] _ in
                    guard let window else { return }
                    self?.onChange?(window.occlusionState.contains(.visible))
                },
            ] + [NSWindow.didResizeNotification, NSWindow.didMoveNotification].map { name in
                NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak window] _ in
                    // SwiftUI places the window after posting the notification, so pin it on the next turn.
                    DispatchQueue.main.async {
                        guard let window, let top = window.screen?.visibleFrame.maxY,
                              abs(window.frame.maxY - top) > 0.5 else { return }
                        window.setFrameTopLeftPoint(NSPoint(x: window.frame.minX, y: top))
                    }
                }
            }
            onChange?(window.occlusionState.contains(.visible))
        }
    }
}
