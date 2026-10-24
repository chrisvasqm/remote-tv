import SwiftUI

/// The remote's materials: a graphite body, slightly lighter keys, a red power key.
enum RemotePalette {
    static let body = Color(red: 0.11, green: 0.11, blue: 0.13)
    static let key = Color(red: 0.19, green: 0.19, blue: 0.22)
    static let okKey = Color(red: 0.27, green: 0.27, blue: 0.31)
    static let edge = Color.white.opacity(0.08)
    static let label = Color(red: 0.92, green: 0.92, blue: 0.94)
    static let power = Color(red: 0.82, green: 0.15, blue: 0.17)
    static let powerArmed = Color(red: 0.95, green: 0.25, blue: 0.20)
    static let active = Color.accentColor
}

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
                    Capsule().fill(fill)
                        .overlay(Capsule().strokeBorder(RemotePalette.edge, lineWidth: 1))
                        .shadow(color: .black.opacity(configuration.isPressed ? 0 : 0.5), radius: 2, y: configuration.isPressed ? 0 : 2)
                }
            }
            .contentShape(Capsule())
            .brightness(configuration.isPressed ? 0.12 : 0)
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

/// One half of a rocker: the whole half is the hit area, and it lights up when pressed.
struct RockerHalfStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(RemotePalette.label)
            .background(Color.white.opacity(configuration.isPressed ? 0.12 : 0))
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}
