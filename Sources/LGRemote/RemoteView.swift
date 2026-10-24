import LGRemoteKit
import SwiftUI

struct RemoteView: View {
    @ObservedObject var model: RemoteModel
    @State private var message = ""
    @State private var confirmPowerOff = false
    @State private var showSettings = false
    @State private var draftHost = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if showSettings {
                settings
            } else if model.status == .connected {
                screen
                controls
                appGrid
                messageField
            } else {
                offline
            }
            if let error = model.lastError {
                Text(error).font(.caption).foregroundStyle(.secondary).lineLimit(3)
            }
            footer
        }
        .padding(14)
        .frame(width: 360)
        .background(PanelVisibility { model.panelVisibilityChanged($0) })
        .onAppear {
            draftHost = model.host
            if model.host.isEmpty { showSettings = true }
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            Circle().fill(statusColor).frame(width: 8, height: 8)
            Text(statusText).font(.headline)
            Spacer()
            if model.status == .connected {
                Text(model.foregroundTitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    private var screen: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(.black)
            if let image = model.screenshot {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
            }
            if model.screenshot == nil || model.screenIsProtected {
                Label(
                    model.screenIsProtected ? "Black screen: this app or input may block capture" : "Loading screen…",
                    systemImage: model.screenIsProtected ? "lock.tv" : "tv"
                )
                .font(.caption).foregroundStyle(.white.opacity(0.7))
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var controls: some View {
        HStack(alignment: .center, spacing: 16) {
            dpad
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    iconButton("backward.end.fill", "Stop") { model.stop() }
                    iconButton("play.fill", "Play") { model.play() }
                    iconButton("pause.fill", "Pause") { model.pause() }
                }
                HStack(spacing: 6) {
                    iconButton("speaker.minus.fill", "Volume down") { model.volumeDown() }
                    iconButton(model.volume?.muted == true ? "speaker.slash.fill" : "speaker.fill", "Mute") {
                        model.toggleMute()
                    }
                    iconButton("speaker.plus.fill", "Volume up") { model.volumeUp() }
                }
                Text(volumeText).font(.caption2).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    iconButton("house.fill", "Home") { model.press("HOME") }
                    iconButton("arrow.uturn.backward", "Back") { model.press("BACK") }
                    iconButton("gearshape.fill", "TV settings") { model.press("MENU") }
                }
                HStack(spacing: 6) {
                    inputMenu
                    iconButton("xmark.app", "Close current app") { model.closeForegroundApp() }
                }
            }
        }
    }

    private var dpad: some View {
        Grid(horizontalSpacing: 4, verticalSpacing: 4) {
            GridRow {
                gap
                iconButton("chevron.up", "Up") { model.press("UP") }
                gap
            }
            GridRow {
                iconButton("chevron.left", "Left") { model.press("LEFT") }
                Button("OK") { model.press("ENTER") }
                    .frame(width: 36, height: 30)
                    .keyboardShortcut(.return, modifiers: [])
                iconButton("chevron.right", "Right") { model.press("RIGHT") }
            }
            GridRow {
                gap
                iconButton("chevron.down", "Down") { model.press("DOWN") }
                gap
            }
        }
    }

    private var gap: some View { Color.clear.frame(width: 1, height: 1) }

    private var inputMenu: some View {
        Menu {
            ForEach(model.inputs) { input in
                Button(input.label + (input.connected ? "" : " (nothing connected)")) { model.switchInput(input) }
            }
        } label: {
            Image(systemName: "rectangle.connected.to.line.below")
        }
        .menuStyle(.borderlessButton)
        .frame(width: 30)
        .help("Inputs")
    }

    private var appGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
            ForEach(model.apps) { app in
                Button { model.launch(app) } label: {
                    Text(app.title).lineLimit(1).frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(app.id == model.foregroundAppId ? .accentColor : nil)
            }
        }
    }

    private var messageField: some View {
        HStack {
            TextField("Message on the TV", text: $message)
                .textFieldStyle(.roundedBorder)
                .onSubmit(sendMessage)
            Button("Send", action: sendMessage).disabled(trimmedMessage.isEmpty)
        }
    }

    private var offline: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(offlineText).font(.callout).fixedSize(horizontal: false, vertical: true)
            HStack {
                if model.status == .networkBlocked {
                    Button("Open Local Network settings") { LocalNetworkAccess.openSettings() }
                } else {
                    Button("Turn TV on") { model.turnOn() }
                }
                if model.status != .pairing && model.status != .connecting {
                    Button("Reconnect") { Task { await model.reconnect() } }
                }
            }
        }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TV address").font(.caption).foregroundStyle(.secondary)
            TextField("192.168.0.10", text: $draftHost)
                .textFieldStyle(.roundedBorder)
                .onSubmit(saveSettings)
            Text("On the TV: Settings > Support > TV information shows the address. Accept the prompt on the TV the first time.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Connect", action: saveSettings)
                    .disabled(draftHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Forget pairing") { model.forgetPairing() }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button(showSettings ? "Done" : "Settings") { showSettings.toggle() }
            Spacer()
            if model.status == .connected {
                Button("Turn off", role: .destructive) { confirmPowerOff = true }
                    .confirmationDialog("Turn the TV off?", isPresented: $confirmPowerOff) {
                        Button("Turn off", role: .destructive) { model.turnOff() }
                    }
            }
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
        .buttonStyle(.borderless)
        .font(.caption)
    }

    // MARK: - Helpers

    private func iconButton(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).frame(width: 22, height: 18)
        }
        .help(help)
    }

    private var trimmedMessage: String { message.trimmingCharacters(in: .whitespaces) }

    private func sendMessage() {
        guard !trimmedMessage.isEmpty else { return }
        model.showMessage(trimmedMessage)
        message = ""
    }

    private func saveSettings() {
        showSettings = false
        Task { await model.setHost(draftHost) }
    }

    private var volumeText: String {
        guard let volume = model.volume else { return "Volume –" }
        return volume.muted ? "Muted" : "Volume \(volume.level)"
    }

    private var statusText: String {
        switch model.status {
        case .idle: return "LG TV"
        case .connecting: return "Connecting…"
        case .pairing: return "Accept the prompt on the TV"
        case .connected: return "TV on"
        case .unreachable: return "TV off or unreachable"
        case .networkBlocked: return "Local Network access needed"
        }
    }

    private var offlineText: String {
        switch model.status {
        case .pairing:
            return "The TV is asking to allow this Mac. Accept it with the TV remote."
        case .networkBlocked:
            return "macOS is blocking LG Remote from the local network. Turn on LG Remote under Privacy & Security > Local Network, then reconnect."
        default:
            return "Can't reach the TV at \(model.host). It may be off or on another network."
        }
    }

    private var statusColor: Color {
        switch model.status {
        case .connected: return .green
        case .connecting, .pairing: return .orange
        case .idle, .unreachable: return .gray
        case .networkBlocked: return .red
        }
    }
}
