import RemoteTVCore
import SwiftUI

extension RemoteView {
    /// A tall pill with + on top and − below, like the volume and channel keys.
    /// Each half takes half the pill, so the whole key is clickable; the label sits
    /// on top in the middle and lets clicks through.
    func rocker(
        _ name: String,
        up: RockerKey,
        down: RockerKey
    ) -> some View {
        VStack(spacing: 0) {
            rockerHalf(up, edge: .top)
            rockerHalf(down, edge: .bottom)
        }
        .frame(width: 38, height: 96)
        .overlay {
            Text(name).font(.caption2.weight(.semibold).monospacedDigit()).foregroundStyle(RemotePalette.label.opacity(0.6))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .background(Capsule().fill(RemotePalette.key).overlay(Capsule().strokeBorder(RemotePalette.edge, lineWidth: 1)))
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.5), radius: 3, y: 2)
    }

    typealias RockerKey = (symbol: String, help: String, action: () -> Void)

    private func rockerHalf(_ half: RockerKey, edge: VerticalEdge) -> some View {
        Button(action: half.action) {
            Image(systemName: half.symbol).font(.system(size: 11, weight: .bold))
                .padding(edge == .top ? .top : .bottom, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: edge == .top ? .top : .bottom)
        }
        .buttonStyle(RockerHalfStyle())
        .help(half.help)
        .accessibilityLabel(half.help)
    }
}
