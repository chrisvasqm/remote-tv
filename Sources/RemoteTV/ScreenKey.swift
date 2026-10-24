import SwiftUI

/// Turns only the picture off (and back on), so the TV never has to be woken.
struct ScreenKey: View {
    let model: RemoteModel

    var body: some View {
        RoundKey(
            title: model.screenIsOff ? "Turn the screen on" : "Turn the screen off",
            symbol: model.screenIsOff ? "sun.max.fill" : "moon.fill",
            size: 26,
            help: model.screenIsOff ? "Turn the screen on" : "Pause and turn the screen off (the TV stays on)",
            action: toggle
        )
        .font(.system(size: 11, weight: .bold))
    }

    private func toggle() {
        if model.screenIsOff {
            model.turnScreenOn()
        } else {
            model.turnScreenOff()
        }
    }
}
