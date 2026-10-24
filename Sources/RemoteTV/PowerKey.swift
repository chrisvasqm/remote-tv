import SwiftUI

/// The red power key. The first press arms it; a second press within 3 seconds turns the TV off.
struct PowerKey: View {
    let model: RemoteModel
    @State private var isArmed = false

    var body: some View {
        Button(action: press) {
            HStack(spacing: 6) {
                Image(systemName: "power").font(.system(size: 11, weight: .bold))
                if isArmed { Text("Turn off?").font(.caption.weight(.semibold)).fixedSize() }
            }
            .padding(.horizontal, isArmed ? 12 : 0)
        }
        .buttonStyle(KeyStyle(
            shape: isArmed ? .capsule : .circle,
            size: CGSize(width: 26, height: 26),
            fill: isArmed ? RemotePalette.powerArmed : RemotePalette.power
        ))
        .fixedSize()
        .animation(.spring(duration: 0.25), value: isArmed)
        .help(isArmed ? "Click again to turn the TV off" : "Turn the TV off")
        .accessibilityLabel(isArmed ? "Confirm: turn the TV off" : "Turn the TV off")
        // Restarts with each arm, so a new arm always gets its full 3 seconds.
        .task(id: isArmed) {
            guard isArmed else { return }
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled { isArmed = false }
        }
    }

    private func press() {
        if isArmed {
            isArmed = false
            model.turnOff()
        } else {
            isArmed = true
        }
    }
}
