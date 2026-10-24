import RemoteTVCore
import SwiftUI

/// The wheel: four arrows around a round OK key, like the remote's navigation ring.
struct NavigationWheel: View {
    let model: RemoteModel
    private static let ring: CGFloat = 116
    private static let reach = ring / 2 - 18

    var body: some View {
        ZStack {
            Circle().fill(RemotePalette.key).strokeBorder(RemotePalette.edge, lineWidth: 1)
                .shadow(color: .black.opacity(0.5), radius: 3, y: 2)
            arrow("Up (↑)", symbol: "chevron.up", key: .up).offset(y: -Self.reach)
            arrow("Down (↓)", symbol: "chevron.down", key: .down).offset(y: Self.reach)
            arrow("Left (←)", symbol: "chevron.left", key: .left).offset(x: -Self.reach)
            arrow("Right (→)", symbol: "chevron.right", key: .right).offset(x: Self.reach)
            Button("OK") { model.press(.ok) }
                .font(.system(size: 13, weight: .semibold))
                .buttonStyle(KeyStyle(shape: .circle, size: CGSize(width: 46, height: 46), fill: RemotePalette.okKey))
                .help("OK (Return)")
        }
        .frame(width: Self.ring, height: Self.ring)
    }

    private func arrow(_ title: String, symbol: String, key: RemoteKey) -> some View {
        Button(title, systemImage: symbol) { model.press(key) }
            .labelStyle(.iconOnly)
            .font(.system(size: 12, weight: .bold))
            .buttonStyle(KeyStyle(shape: .circle, size: CGSize(width: 34, height: 34), fill: nil))
            .help(title)
    }
}
