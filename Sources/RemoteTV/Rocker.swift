import SwiftUI

/// A tall pill with + on top and − below, like the volume and channel keys.
/// Each half takes half the pill, so the whole key is clickable; the name sits
/// on top in the middle and lets clicks through.
struct Rocker: View {
    struct Key {
        let symbol: String
        let help: String
        let action: () -> Void
    }

    static let width: CGFloat = 38
    let name: String
    let up: Key
    let down: Key

    var body: some View {
        VStack(spacing: 0) {
            half(up, edge: .top)
            half(down, edge: .bottom)
        }
        .frame(width: Self.width, height: 96)
        .overlay {
            Text(name)
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(RemotePalette.label.opacity(0.6))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .background { Capsule().fill(RemotePalette.key).strokeBorder(RemotePalette.edge, lineWidth: 1) }
        .clipShape(.capsule)
        .shadow(color: .black.opacity(0.5), radius: 3, y: 2)
    }

    /// The padding and frame sit inside the label, so the whole half is the hit area.
    private func half(_ key: Key, edge: VerticalEdge) -> some View {
        Button(action: key.action) {
            Label(key.help, systemImage: key.symbol)
                .labelStyle(.iconOnly)
                .font(.system(size: 11, weight: .bold))
                .padding(edge == .top ? .top : .bottom, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: edge == .top ? .top : .bottom)
        }
        .buttonStyle(RockerHalfStyle())
        .help(key.help)
    }
}
