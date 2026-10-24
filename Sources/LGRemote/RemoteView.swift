import LGRemoteKit
import SwiftUI

struct RemoteView: View {
    @ObservedObject var model: RemoteModel
    @State private var message = ""
    @State private var confirmPowerOff = false
    @State private var showSettings = false
    @State private var draftHost = ""
    @FocusState private var remoteFocused: Bool

    private static let presets = ["Bedtime in 10 min", "Dinner is ready", "Screen time is over"]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if showSettings {
                settings
            } else if model.status == .connected {
                screen
                Toggle("Smooth preview (about 2 frames a second)", isOn: $model.smoothPreview)
                    .toggleStyle(.switch).controlSize(.mini).font(.caption)
                    .help("Captures frames back to back. Uses more network traffic, about 250 KB per second.")
                controls
                Divider()
                appGrid
                Divider()
                messages
            } else {
                offline
            }
            if let error = model.lastError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(3)
            }
            footer
        }
        .padding(16)
        .frame(width: 440)
        .background(PanelVisibility { model.panelVisibilityChanged($0) })
        .onAppear {
            draftHost = model.host
            if model.host.isEmpty { showSettings = true }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Circle().fill(statusColor).frame(width: 8, height: 8)
            Text(statusText).font(.headline)
            Spacer()
            if model.status == .connected {
                Button { confirmPowerOff = true } label: {
                    Image(systemName: "power").font(.title3)
                }
                .buttonStyle(.borderless)
                .help("Turn the TV off")
                .confirmationDialog("Turn the TV off?", isPresented: $confirmPowerOff) {
                    Button("Turn off", role: .destructive) { model.turnOff() }
                }
            }
        }
    }

    // MARK: - Live screen

    private var screen: some View {
        Color.black
            .aspectRatio(16 / 9, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay {
                if let image = model.screenshot {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                }
                if model.screenshot == nil || model.screenIsProtected {
                    Label(
                        model.screenIsProtected ? "This app or input hides its picture" : "Loading the screen…",
                        systemImage: model.screenIsProtected ? "eye.slash" : "tv"
                    )
                    .font(.callout).foregroundStyle(.white.opacity(0.75))
                }
            }
            .overlay(alignment: .bottomLeading) {
                HStack(spacing: 6) {
                    Circle().fill(.red).frame(width: 6, height: 6)
                    Text(model.foregroundTitle).font(.caption.weight(.semibold))
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(.black.opacity(0.6), in: Capsule())
                .foregroundStyle(.white)
                .padding(8)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("TV screen, showing \(model.foregroundTitle)")
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(alignment: .center, spacing: 20) {
            dpad
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    remoteButton("play.fill", "Play") { model.play() }
                    remoteButton("pause.fill", "Pause (Space)") { model.pause() }
                    remoteButton("stop.fill", "Stop") { model.stop() }
                }
                HStack(spacing: 6) {
                    remoteButton("speaker.minus.fill", "Volume down") { model.volumeDown() }
                    remoteButton(model.volume?.muted == true ? "speaker.slash.fill" : "speaker.fill", "Mute") {
                        model.toggleMute()
                    }
                    remoteButton("speaker.plus.fill", "Volume up") { model.volumeUp() }
                    Text(volumeText).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    remoteButton("house.fill", "Home") { model.press("HOME") }
                    remoteButton("arrow.uturn.backward", "Back (Delete)") { model.press("BACK") }
                    remoteButton("gearshape.fill", "TV settings") { model.press("MENU") }
                    inputMenu
                }
            }
        }
        .focusable()
        .focused($remoteFocused)
        .focusEffectDisabled()
        .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow, .return, .delete, .space]) { press in
            switch press.key {
            case .upArrow: model.press("UP")
            case .downArrow: model.press("DOWN")
            case .leftArrow: model.press("LEFT")
            case .rightArrow: model.press("RIGHT")
            case .return: model.press("ENTER")
            case .delete: model.press("BACK")
            default: model.pause()
            }
            return .handled
        }
        .onTapGesture { remoteFocused = true }
    }

    private var dpad: some View {
        Grid(horizontalSpacing: 4, verticalSpacing: 4) {
            GridRow {
                gap
                remoteButton("chevron.up", "Up (↑)") { model.press("UP") }
                gap
            }
            GridRow {
                remoteButton("chevron.left", "Left (←)") { model.press("LEFT") }
                Button { model.press("ENTER") } label: {
                    Text("OK").font(.callout.weight(.semibold)).frame(width: 34, height: 28)
                }
                .buttonStyle(.borderedProminent)
                .help("OK (Return)")
                remoteButton("chevron.right", "Right (→)") { model.press("RIGHT") }
            }
            GridRow {
                gap
                remoteButton("chevron.down", "Down (↓)") { model.press("DOWN") }
                gap
            }
        }
    }

    private var gap: some View { Color.clear.frame(width: 1, height: 1) }

    private var inputMenu: some View {
        Menu {
            ForEach(model.inputs) { input in
                Button(input.label + (input.connected ? "" : " (nothing plugged in)")) { model.switchInput(input) }
            }
        } label: {
            Text("Input")
        }
        .menuStyle(.button)
        .fixedSize()
        .help("Switch to an HDMI input")
    }

    // MARK: - Apps

    private var appGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Open an app").font(.subheadline.weight(.semibold))
                Spacer()
                if model.foregroundAppId != TVApp.homeId {
                    Button("Close \(model.foregroundTitle)") { model.closeForegroundApp() }
                        .buttonStyle(.borderless).font(.caption)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                ForEach(launchableApps) { app in
                    Button { model.launch(app) } label: {
                        Text(app.title).lineLimit(1).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .tint(app.id == model.foregroundAppId ? .accentColor : nil)
                }
            }
        }
    }

    /// HDMI ports are under Input, so they are left out of the app grid.
    private var launchableApps: [TVApp] {
        model.apps.filter { !$0.id.hasPrefix("com.webos.app.hdmi") }
    }

    // MARK: - Messages

    private var messages: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Show a message on the TV").font(.subheadline.weight(.semibold))
            HStack(spacing: 6) {
                ForEach(Self.presets, id: \.self) { preset in
                    Button(preset) { model.showMessage(preset) }
                        .buttonStyle(.bordered).controlSize(.small)
                }
            }
            HStack {
                TextField("Your message", text: $message)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(sendMessage)
                Button("Show", action: sendMessage).disabled(trimmedMessage.isEmpty)
            }
            if let sent = model.lastMessageSent {
                Label("Shown on the TV: \(sent)", systemImage: "checkmark.circle")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    // MARK: - Offline and settings

    private var offline: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(offlineText).font(.callout).fixedSize(horizontal: false, vertical: true)
            HStack {
                switch model.status {
                case .networkBlocked:
                    Button("Open Local Network settings") { LocalNetworkAccess.openSettings() }
                        .buttonStyle(.borderedProminent)
                case .pairing, .connecting:
                    ProgressView().controlSize(.small)
                default:
                    Button("Turn the TV on") { model.turnOn() }.buttonStyle(.borderedProminent)
                }
                if model.status != .pairing && model.status != .connecting {
                    Button("Try again") { Task { await model.reconnect() } }
                }
            }
        }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TV address").font(.subheadline.weight(.semibold))
            TextField("192.168.0.10", text: $draftHost)
                .textFieldStyle(.roundedBorder)
                .onSubmit(saveSettings)
            Text("Find it on the TV under Settings > Support > TV information. The first time, accept the prompt on the TV with its remote.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Connect", action: saveSettings)
                    .buttonStyle(.borderedProminent)
                    .disabled(draftHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Spacer()
                Button("Unpair this Mac", role: .destructive) { model.forgetPairing() }
                    .help("Remove the saved pairing. The TV asks again next time.")
            }
        }
    }

    private var footer: some View {
        HStack {
            Button(showSettings ? "Done" : "Settings") { showSettings.toggle() }
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
        .buttonStyle(.borderless)
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    // MARK: - Helpers

    private func remoteButton(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).frame(width: 26, height: 22)
        }
        .help(help)
        .accessibilityLabel(help)
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
        guard let volume = model.volume else { return "" }
        return volume.muted ? "Muted" : "\(volume.level)"
    }

    private var statusText: String {
        switch model.status {
        case .idle: return "LG TV"
        case .connecting: return "Connecting…"
        case .pairing: return "Waiting for the TV"
        case .connected: return "TV is on"
        case .unreachable: return "TV is off or out of reach"
        case .networkBlocked: return "Local Network access needed"
        }
    }

    private var offlineText: String {
        switch model.status {
        case .pairing:
            return "The TV is asking whether to allow this Mac. Accept it with the TV remote."
        case .connecting:
            return "Connecting to the TV at \(model.host)."
        case .networkBlocked:
            return "macOS blocks LG Remote from your local network. Turn on LG Remote under Privacy & Security > Local Network, then try again."
        default:
            return "Can't reach the TV at \(model.host). If it is off, turn it on here. Otherwise check that the Mac and the TV are on the same Wi-Fi."
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
