import RemoteTVCore
import SwiftUI

/// The TV's inputs. Inputs with nothing plugged in are listed, but marked.
struct InputMenu: View {
    let model: RemoteModel

    var body: some View {
        Menu("Input", systemImage: "rectangle.portrait.and.arrow.right") {
            ForEach(model.inputs) { input in
                Button(input.connected ? input.label : "\(input.label) (nothing plugged in)") {
                    model.switchInput(input)
                }
            }
        }
        .menuStyle(.button)
        .fixedSize()
        .help("Switch input")
    }
}
