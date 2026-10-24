import SwiftUI

/// One half of a rocker: the whole half is the hit area, and it lights up when pressed.
struct RockerHalfStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(RemotePalette.label)
            .background(Color.white.opacity(configuration.isPressed ? 0.12 : 0))
            .contentShape(.rect)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}
