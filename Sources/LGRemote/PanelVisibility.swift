import AppKit
import SwiftUI

/// Reports when the menu-bar panel is shown or hidden. onAppear/onDisappear are not
/// called reliably for MenuBarExtra windows, but the window's occlusion state is.
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
        private var observer: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observer.map(NotificationCenter.default.removeObserver)
            guard let window else { return }
            observer = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
            ) { [weak self, weak window] _ in
                guard let window else { return }
                self?.onChange?(window.occlusionState.contains(.visible))
            }
            onChange?(window.occlusionState.contains(.visible))
        }
    }
}
