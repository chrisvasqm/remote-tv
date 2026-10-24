import RemoteTVCore
import SwiftUI

struct RemoteView: View {
    let model: RemoteModel
    @State var message = ""
    /// The first press arms the power key; a second press within a few seconds turns the TV off.
    @State var powerArmed = false
    @State var showSettings = false
    @State private var showMessages = false
    @State var draftHost = ""
    @FocusState var remoteFocused: Bool

    private static let panelWidth: CGFloat = 280
    private static let padding: CGFloat = 14
    /// The menu-bar window sizes itself to its content, so the 16:9 preview needs a fixed size.
    static let previewWidth = panelWidth - 2 * padding

    var body: some View {
        VStack(spacing: 10) {
            header
            if showSettings {
                settings
            } else if model.status == .connected {
                if can(.screenshot) { screen }
                controls
                if can(.apps) { appKeys }
                if showMessages { messages }
            } else {
                offline
            }
            if let error = model.lastError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(Remote.label.opacity(0.7)).lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            footer
        }
        .padding(Self.padding)
        .frame(width: Self.panelWidth)
        .background(Remote.body)
        .environment(\.colorScheme, .dark)
        .background(PanelVisibility { model.panelVisibilityChanged($0) })
        .onAppear {
            draftHost = model.host
            if model.host.isEmpty { showSettings = true }
        }
    }

    private var footer: some View {
        HStack {
            Button(showSettings ? "Done" : "Settings") { showSettings.toggle() }
            if model.status == .connected && !showSettings && can(.messages) {
                Button(showMessages ? "Hide message" : "Message") { showMessages.toggle() }
                    .help("Show a message on the TV")
            }
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
        .buttonStyle(.borderless)
        .font(.caption)
        .foregroundStyle(Remote.label.opacity(0.6))
    }

    // MARK: - Helpers

    func can(_ capability: TVCapabilities) -> Bool {
        brand.supports(capability)
    }
}
