import RemoteTVCore
import SwiftUI

extension RemoteView {
    // MARK: - Header

    /// Power on the left and Input on the right, where a TV remote has them.
    var header: some View {
        HStack(spacing: 8) {
            if model.status == .connected {
                if can(.powerOff) { powerKey }
                if can(.screenOff) { screenKey }
            }
            Circle().fill(statusColor).frame(width: 6, height: 6)
            Text(statusText).font(.caption.weight(.medium)).foregroundStyle(Remote.label)
            Spacer()
            if model.status == .connected && can(.inputs) { inputMenu }
        }
    }

    private var powerKey: some View {
        Button {
            if powerArmed {
                powerArmed = false
                model.turnOff()
            } else {
                powerArmed = true
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    powerArmed = false
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "power").font(.system(size: 11, weight: .bold))
                if powerArmed { Text("Turn off?").font(.caption.weight(.semibold)).fixedSize() }
            }
            .padding(.horizontal, powerArmed ? 12 : 0)
        }
        .buttonStyle(KeyStyle(
            shape: powerArmed ? .capsule : .circle,
            size: CGSize(width: 26, height: 26),
            fill: powerArmed ? Remote.powerArmed : Remote.power
        ))
        .fixedSize()
        .animation(.spring(duration: 0.25), value: powerArmed)
        .help(powerArmed ? "Click again to turn the TV off" : "Turn the TV off")
        .accessibilityLabel(powerArmed ? "Confirm: turn the TV off" : "Turn the TV off")
    }

    /// Turns only the picture off (and back on), so the TV never has to be woken.
    private var screenKey: some View {
        Button {
            model.screenIsOff ? model.turnScreenOn() : model.turnScreenOff()
        } label: {
            Image(systemName: model.screenIsOff ? "sun.max.fill" : "moon.fill").font(.system(size: 11, weight: .bold))
        }
        .buttonStyle(KeyStyle(shape: .circle, size: CGSize(width: 26, height: 26), fill: Remote.key))
        .help(model.screenIsOff ? "Turn the screen on" : "Pause and turn the screen off (the TV stays on)")
        .accessibilityLabel(model.screenIsOff ? "Turn the screen on" : "Turn the screen off")
    }

    private var inputMenu: some View {
        Menu {
            ForEach(model.inputs) { input in
                Button(input.label + (input.connected ? "" : " (nothing plugged in)")) { model.switchInput(input) }
            }
        } label: {
            Label("Input", systemImage: "rectangle.portrait.and.arrow.right")
        }
        .menuStyle(.button)
        .fixedSize()
        .help("Switch input")
    }

    private var statusText: String {
        switch model.status {
        case .idle: return brand.displayName
        case .connecting: return "Connecting…"
        case .pairing: return "Waiting for the TV"
        case .connected: return "TV is on"
        case .unreachable: return "TV is off or out of reach"
        case .networkBlocked: return "Local Network access needed"
        }
    }

    private var statusColor: Color {
        switch model.status {
        case .connected: return .green
        case .connecting, .pairing: return .orange
        case .networkBlocked: return .red
        case .idle, .unreachable: return .gray
        }
    }
}
