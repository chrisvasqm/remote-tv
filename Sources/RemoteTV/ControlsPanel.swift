import RemoteTVCore
import SwiftUI

/// Volume and channel rockers around the wheel, then the round keys. Click the
/// panel, then use the arrow keys, Return, Delete and Space on the Mac keyboard.
struct ControlsPanel: View {
    let model: RemoteModel
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Rocker(
                    name: volumeText,
                    up: Rocker.Key(symbol: "plus", help: "Volume up", action: model.volumeUp),
                    down: Rocker.Key(symbol: "minus", help: "Volume down", action: model.volumeDown)
                )
                Spacer()
                NavigationWheel(model: model)
                Spacer()
                if brand.supports(.channels) {
                    Rocker(
                        name: "Ch",
                        up: Rocker.Key(symbol: "chevron.up", help: "Channel up") { model.press(.channelUp) },
                        down: Rocker.Key(symbol: "chevron.down", help: "Channel down") { model.press(.channelDown) }
                    )
                } else {
                    // Keeps the wheel centred.
                    Color.clear.frame(width: Rocker.width, height: 1)
                }
            }
            HStack(spacing: 12) {
                RoundKey(title: "Back (Delete)", symbol: "arrow.uturn.backward") { model.press(.back) }
                RoundKey(title: "Home", symbol: "house.fill") { model.press(.home) }
                RoundKey(title: "TV settings", symbol: "gearshape.fill") { model.press(.settings) }
                RoundKey(
                    title: "Mute",
                    symbol: model.volume?.muted == true ? "speaker.slash.fill" : "speaker.wave.2.fill",
                    action: model.toggleMute
                )
            }
            .font(.system(size: 12, weight: .semibold))
            HStack(spacing: 12) {
                RoundKey(title: "Play", symbol: "play.fill", action: model.play)
                RoundKey(title: "Pause (Space)", symbol: "pause.fill", action: model.pause)
                RoundKey(title: "Stop", symbol: "stop.fill", action: model.stop)
            }
            .font(.system(size: 12, weight: .semibold))
        }
        .padding(.vertical, 4)
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow, .return, .delete, .space], action: handle)
        // A click anywhere on the remote gives it keyboard focus; the keys stay buttons.
        .onTapGesture { isFocused = true }
    }

    private var volumeText: String {
        guard let volume = model.volume else { return "Vol" }
        return volume.muted ? "Muted" : "\(volume.level)"
    }

    private func handle(_ press: KeyPress) -> KeyPress.Result {
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
}
