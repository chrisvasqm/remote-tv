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
