import CoreGraphics

/// The panel's fixed sizes. The menu-bar window sizes itself to its content,
/// so the 16:9 preview needs a fixed width.
enum PanelMetrics {
    static let panelWidth: CGFloat = 280
    static let padding: CGFloat = 14
    static let previewWidth = panelWidth - 2 * padding
}
