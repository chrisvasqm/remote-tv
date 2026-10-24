import RemoteTVCore
import SwiftUI

extension RemoteView {
    // MARK: - Controls

    var controls: some View {
        VStack(spacing: 8) {
            HStack {
                rocker(volumeText.isEmpty ? "Vol" : volumeText, up: ("plus", "Volume up", model.volumeUp), down: ("minus", "Volume down", model.volumeDown))
                Spacer()
                dpad
                Spacer()
                if can(.channels) {
                    rocker("Ch", up: ("chevron.up", "Channel up", { model.press(.channelUp) }),
                           down: ("chevron.down", "Channel down", { model.press(.channelDown) }))
                } else {
                    // Keeps the wheel centred.
                    Color.clear.frame(width: 38, height: 1)
                }
            }
            HStack(spacing: 12) {
                key("arrow.uturn.backward", "Back (Delete)") { model.press(.back) }
                key("house.fill", "Home") { model.press(.home) }
                key("gearshape.fill", "TV settings") { model.press(.settings) }
                key(model.volume?.muted == true ? "speaker.slash.fill" : "speaker.wave.2.fill", "Mute") {
                    model.toggleMute()
                }
            }
            HStack(spacing: 12) {
                key("play.fill", "Play") { model.play() }
                key("pause.fill", "Pause (Space)") { model.pause() }
                key("stop.fill", "Stop") { model.stop() }
            }
        }
        .padding(.vertical, 4)
        .focusable()
        .focused($remoteFocused)
        .focusEffectDisabled()
        .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow, .return, .delete, .space]) { press in
            switch press.key {
            case .upArrow: model.press(.up)
            case .downArrow: model.press(.down)
            case .leftArrow: model.press(.left)
            case .rightArrow: model.press(.right)
            case .return: model.press(.ok)
            case .delete: model.press(.back)
            default: model.pause()
            }
            return .handled
        }
        .onTapGesture { remoteFocused = true }
    }

    /// The wheel: four arrows around a round OK key, like the remote's navigation ring.
    private var dpad: some View {
        let ring: CGFloat = 116
        let reach = ring / 2 - 18
        return ZStack {
            Circle().fill(Remote.key)
                .overlay(Circle().strokeBorder(Remote.edge, lineWidth: 1))
                .shadow(color: .black.opacity(0.5), radius: 3, y: 2)
            arrowKey("chevron.up", "Up (↑)", .up).offset(y: -reach)
            arrowKey("chevron.down", "Down (↓)", .down).offset(y: reach)
            arrowKey("chevron.left", "Left (←)", .left).offset(x: -reach)
            arrowKey("chevron.right", "Right (→)", .right).offset(x: reach)
            Button { model.press(.ok) } label: {
                Text("OK").font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(KeyStyle(shape: .circle, size: CGSize(width: 46, height: 46), fill: Remote.okKey))
            .help("OK (Return)")
        }
        .frame(width: ring, height: ring)
    }

    private func arrowKey(_ symbol: String, _ help: String, _ key: RemoteKey) -> some View {
        Button { model.press(key) } label: {
            Image(systemName: symbol).font(.system(size: 12, weight: .bold))
        }
        .buttonStyle(KeyStyle(shape: .circle, size: CGSize(width: 34, height: 34), fill: nil))
        .help(help)
        .accessibilityLabel(help)
    }

    private func key(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
        }
        .buttonStyle(KeyStyle(shape: .circle, size: CGSize(width: 30, height: 30), fill: Remote.key))
        .help(help)
        .accessibilityLabel(help)
    }

    private var volumeText: String {
        guard let volume = model.volume else { return "" }
        return volume.muted ? "Muted" : "\(volume.level)"
    }
}
