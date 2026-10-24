import RemoteTVCore
import SwiftUI

/// The menu-bar panel, drawn as a TV remote. Each section is its own view, so a new
/// live-view frame redraws only the preview.
struct RemoteView: View {
    let model: RemoteModel
    @State private var showSettings = false
    @State private var showMessages = false
    /// Kept here, so an address typed but not saved survives closing Settings.
    @State private var draftHost = ""

    var body: some View {
        VStack(spacing: 10) {
            HeaderBar(model: model)
            if showSettings {
                SettingsPanel(model: model, isShown: $showSettings, draftHost: $draftHost)
            } else if model.status == .connected {
                if brand.supports(.screenshot) { ScreenPreview(model: model) }
                ControlsPanel(model: model)
                if brand.supports(.apps) { AppKeys(model: model) }
                if showMessages { MessagesPanel(model: model) }
            } else {
                OfflinePanel(model: model)
            }
            if let error = model.lastError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(RemotePalette.label.opacity(0.7)).lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            FooterBar(model: model, showSettings: $showSettings, showMessages: $showMessages)
        }
        .padding(PanelMetrics.padding)
        .frame(width: PanelMetrics.panelWidth)
        .background(RemotePalette.body)
        .environment(\.colorScheme, .dark)
        .background(PanelVisibility { model.panelVisibilityChanged($0) })
        .onAppear(perform: loadHost)
    }

    private func loadHost() {
        draftHost = model.host
        if model.host.isEmpty { showSettings = true }
    }
}
