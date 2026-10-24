import SwiftUI

/// A physical key: a raised shape that sinks a little when pressed.
struct KeyStyle: ButtonStyle {
    /// A circle key has a fixed square size; a capsule key stretches to its width.
    /// Both draw a `Capsule`, which is a circle in a square frame.
    enum Shape { case circle, capsule }
    let shape: Shape
    let size: CGSize
    /// Nil for keys drawn on another key's surface, such as the wheel's arrows.
    let fill: Color?

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(RemotePalette.label)
            .frame(minWidth: size.width, maxWidth: shape == .capsule ? .infinity : size.width)
            .frame(height: size.height)
            .background {
                if let fill {
                    Capsule().fill(fill).strokeBorder(RemotePalette.edge, lineWidth: 1)
                        .shadow(
                            color: .black.opacity(configuration.isPressed ? 0 : 0.5),
                            radius: 2, y: configuration.isPressed ? 0 : 2
                        )
                }
            }
            .contentShape(.capsule)
            .brightness(configuration.isPressed ? 0.12 : 0)
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}
