import SwiftUI

/// A small round key, such as Home or Play. The title is the tooltip and the VoiceOver label.
struct RoundKey: View {
    let title: String
    let symbol: String
    let action: () -> Void

    init(_ title: String, symbol: String, action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.action = action
    }

    var body: some View {
        Button(title, systemImage: symbol, action: action)
            .labelStyle(.iconOnly)
            .font(.system(size: 12, weight: .semibold))
            .buttonStyle(KeyStyle(shape: .circle, size: CGSize(width: 30, height: 30), fill: RemotePalette.key))
            .help(title)
    }
}
