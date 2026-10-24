import SwiftUI

/// Settings, the message panel and Quit, under the remote.
struct FooterBar: View {
    let model: RemoteModel
    @Binding var showSettings: Bool
    @Binding var showMessages: Bool

    var body: some View {
        HStack {
            Button(showSettings ? "Done" : "Settings") { showSettings.toggle() }
            if model.status == .connected && !showSettings && brand.supports(.messages) {
                Button(showMessages ? "Hide message" : "Message") { showMessages.toggle() }
                    .help("Show a message on the TV")
            }
            Spacer()
            Button("Quit", action: quit)
        }
        .buttonStyle(.borderless)
        .font(.caption)
        .foregroundStyle(RemotePalette.label.opacity(0.6))
    }

    private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
