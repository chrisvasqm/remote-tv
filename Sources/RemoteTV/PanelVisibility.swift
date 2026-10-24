import AppKit
import SwiftUI

/// Reports when the menu-bar panel is shown or hidden. onAppear/onDisappear are not
/// called reliably for MenuBarExtra windows, but the window's occlusion state is.
///
/// It also keeps the panel fitted to its content, right under the menu bar.
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
        /// Read in deinit, which is not main-actor isolated; only touched on the main thread.
        nonisolated(unsafe) private var observers: [NSObjectProtocol] = []

        deinit {
            observers.forEach(NotificationCenter.default.removeObserver)
        }

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
                NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    self?.fitSoon()
                }
            }
            onChange?(window.occlusionState.contains(.visible))
        }

        /// The view fills the panel's content. MenuBarExtra grows the window with the
        /// content but never shrinks it, so a short screen (settings, TV off) sat at the
        /// bottom of a tall window, far below the menu bar.
        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            fitSoon()
        }

        /// SwiftUI places the window after these events, so fit it on the next turn:
        /// as tall as the content, with its top edge under the menu bar.
        private func fitSoon() {
            RunLoop.main.perform { [weak self] in
                guard let self, let window, let top = window.screen?.visibleFrame.maxY,
                      bounds.height > 0 else { return }
                let content = NSRect(x: window.frame.minX, y: 0, width: window.frame.width, height: bounds.height)
                var frame = window.frameRect(forContentRect: content)
                frame.origin.y = top - frame.height
                guard window.frame != frame else { return }
                window.setFrame(frame, display: true)
            }
        }
    }
}
