import SwiftUI

/// Turns only the picture off (and back on), so the TV never has to be woken.
struct ScreenKey: View {
    let model: RemoteModel

    var body: some View {
        Button(
            model.screenIsOff ? "Turn the screen on" : "Turn the screen off",
            systemImage: model.screenIsOff ? "sun.max.fill" : "moon.fill",
            action: toggle
        )
        .labelStyle(.iconOnly)
        .font(.system(size: 11, weight: .bold))
        .buttonStyle(KeyStyle(shape: .circle, size: CGSize(width: 26, height: 26), fill: RemotePalette.key))
        .help(model.screenIsOff ? "Turn the screen on" : "Pause and turn the screen off (the TV stays on)")
    }

    private func toggle() {
        if model.screenIsOff {
            model.turnScreenOn()
        } else {
            model.turnScreenOff()
        }
    }
}
