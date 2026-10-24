import SwiftUI

/// A round key with a symbol, such as Home, Play or a wheel arrow. The title is the
/// VoiceOver label and, unless `help` is given, the tooltip. Callers set the symbol's font.
struct RoundKey: View {
    let title: String
    let symbol: String
    var size: CGFloat = 30
    /// Nil for keys drawn on another key's surface, such as the wheel's arrows.
    var fill: Color? = RemotePalette.key
    var help: String?
    let action: () -> Void

    var body: some View {
        Button(title, systemImage: symbol, action: action)
            .labelStyle(.iconOnly)
            .buttonStyle(KeyStyle(shape: .circle, size: CGSize(width: size, height: size), fill: fill))
            .help(help ?? title)
    }
}
