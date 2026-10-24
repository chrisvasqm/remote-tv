import RemoteTVCore
import SwiftUI

struct RemoteView: View {
    let model: RemoteModel
    @State private var message = ""
    /// The first press arms the power key; a second press within a few seconds turns the TV off.
    @State private var powerArmed = false
    @State private var showSettings = false
    @State private var showMessages = false
    @State private var draftHost = ""
    @FocusState private var remoteFocused: Bool

    private static let panelWidth: CGFloat = 280
    private static let padding: CGFloat = 14
    /// The menu-bar window sizes itself to its content, so the 16:9 preview needs a fixed size.
    private static let previewWidth = panelWidth - 2 * padding

    private static let presets = ["Bedtime in 10 min", "Dinner is ready", "Screen time is over"]

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

    // MARK: - Header

    /// Power on the left and Input on the right, where a TV remote has them.
    private var header: some View {
        HStack(spacing: 8) {
            if model.status == .connected {
                if can(.powerOff) { powerKey }
                if can(.screenOff) { screenKey }
            }
            Circle().fill(statusColor).frame(width: 6, height: 6)
            Text(statusText).font(.caption.weight(.medium)).foregroundStyle(Remote.label)
            Spacer()
            if model.status == .connected && can(.inputs) { inputMenu }
        }
    }

    private var powerKey: some View {
        Button {
            if powerArmed {
                powerArmed = false
                model.turnOff()
            } else {
                powerArmed = true
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    powerArmed = false
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "power").font(.system(size: 11, weight: .bold))
                if powerArmed { Text("Turn off?").font(.caption.weight(.semibold)).fixedSize() }
            }
            .padding(.horizontal, powerArmed ? 12 : 0)
        }
        .buttonStyle(KeyStyle(
            shape: powerArmed ? .capsule : .circle,
            size: CGSize(width: 26, height: 26),
            fill: powerArmed ? Remote.powerArmed : Remote.power
        ))
        .fixedSize()
        .animation(.spring(duration: 0.25), value: powerArmed)
        .help(powerArmed ? "Click again to turn the TV off" : "Turn the TV off")
        .accessibilityLabel(powerArmed ? "Confirm: turn the TV off" : "Turn the TV off")
    }

    /// Turns only the picture off (and back on), so the TV never has to be woken.
    private var screenKey: some View {
        Button {
            model.screenIsOff ? model.turnScreenOn() : model.turnScreenOff()
        } label: {
            Image(systemName: model.screenIsOff ? "sun.max.fill" : "moon.fill").font(.system(size: 11, weight: .bold))
        }
        .buttonStyle(KeyStyle(shape: .circle, size: CGSize(width: 26, height: 26), fill: Remote.key))
        .help(model.screenIsOff ? "Turn the screen on" : "Pause and turn the screen off (the TV stays on)")
        .accessibilityLabel(model.screenIsOff ? "Turn the screen on" : "Turn the screen off")
    }

    // MARK: - Live screen

    private var screen: some View {
        Color.black
            .frame(width: Self.previewWidth, height: Self.previewWidth * 9 / 16)
            .overlay {
                if let image = model.screenshot {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                }
                if model.screenIsOff {
                    VStack(spacing: 8) {
                        Label("The screen is off", systemImage: "moon.fill")
                            .font(.callout).foregroundStyle(.white.opacity(0.75))
                        Button("Turn the screen on") { model.turnScreenOn() }
                            .buttonStyle(.borderedProminent).controlSize(.small)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
                } else if model.screenshot == nil || model.screenIsProtected {
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
                    if !model.isHome {
                        Button { model.closeForegroundApp() } label: {
                            Image(systemName: "xmark").font(.caption2.weight(.bold))
                        }
                        .buttonStyle(.borderless)
                        .help("Close \(model.foregroundTitle)")
                        .accessibilityLabel("Close \(model.foregroundTitle)")
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(.black.opacity(0.6), in: Capsule())
                .foregroundStyle(.white)
                .padding(8)
            }
            .overlay(alignment: .bottomTrailing) {
                if let fps = model.framesPerSecond {
                    Text(String(format: "%.1f fps", fps))
                        .font(.caption2.monospacedDigit())
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(.black.opacity(0.6), in: Capsule())
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(8)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            // A bezel, so the preview reads as the TV's screen set into the remote.
            .padding(4)
            .background(Color.black, in: RoundedRectangle(cornerRadius: 12))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("TV screen, showing \(model.foregroundTitle)")
    }

    // MARK: - Controls

    private var controls: some View {
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

    /// A tall pill with + on top and − below, like the volume and channel keys.
    /// Each half takes half the pill, so the whole key is clickable; the label sits
    /// on top in the middle and lets clicks through.
    private func rocker(
        _ name: String,
        up: RockerKey,
        down: RockerKey
    ) -> some View {
        VStack(spacing: 0) {
            rockerHalf(up, edge: .top)
            rockerHalf(down, edge: .bottom)
        }
        .frame(width: 38, height: 96)
        .overlay {
            Text(name).font(.caption2.weight(.semibold).monospacedDigit()).foregroundStyle(Remote.label.opacity(0.6))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .background(Capsule().fill(Remote.key).overlay(Capsule().strokeBorder(Remote.edge, lineWidth: 1)))
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.5), radius: 3, y: 2)
    }

    private typealias RockerKey = (symbol: String, help: String, action: () -> Void)

    private func rockerHalf(_ half: RockerKey, edge: VerticalEdge) -> some View {
        Button(action: half.action) {
            Image(systemName: half.symbol).font(.system(size: 11, weight: .bold))
                .padding(edge == .top ? .top : .bottom, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: edge == .top ? .top : .bottom)
        }
        .buttonStyle(RockerHalfStyle())
        .help(half.help)
        .accessibilityLabel(half.help)
    }

    private var inputMenu: some View {
        Menu {
            ForEach(model.inputs) { input in
                Button(input.label + (input.connected ? "" : " (nothing plugged in)")) { model.switchInput(input) }
            }
        } label: {
            Label("Input", systemImage: "rectangle.portrait.and.arrow.right")
        }
        .menuStyle(.button)
        .fixedSize()
        .help("Switch input")
    }

    // MARK: - Apps

    /// The app shortcut keys at the bottom of the remote, three to a row.
    /// A short last row is centred, the way keys sit on a remote.
    private var appKeys: some View {
        let columns = 3
        let spacing: CGFloat = 5
        let width = (Self.previewWidth - spacing * CGFloat(columns - 1)) / CGFloat(columns)
        let apps = model.apps
        let rows = stride(from: 0, to: apps.count, by: columns).map { Array(apps[$0..<min($0 + columns, apps.count)]) }
        return VStack(spacing: spacing) {
            ForEach(rows, id: \.first?.id) { row in
                HStack(spacing: spacing) {
                    ForEach(row) { app in
                        Button { model.launch(app) } label: {
                            Text(app.title).font(.caption2.weight(.semibold))
                                .lineLimit(1).minimumScaleFactor(0.8).padding(.horizontal, 4)
                        }
                        .buttonStyle(KeyStyle(
                            shape: .capsule, size: CGSize(width: width, height: 22),
                            fill: app.id == model.foregroundAppId ? Remote.active : Remote.key
                        ))
                        .frame(width: width)
                    }
                }
            }
        }
    }

    // MARK: - Messages

    private var messages: some View {
        VStack(alignment: .leading, spacing: 8) {
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
        .font(.callout)
        .foregroundStyle(Remote.label)
    }

    // MARK: - Offline and settings

    private var offline: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(offlineText).font(.callout).foregroundStyle(Remote.label).fixedSize(horizontal: false, vertical: true)
            HStack {
                if model.status == .networkBlocked {
                    Button("Open Local Network settings") { LocalNetworkAccess.openSettings() }
                        .buttonStyle(.borderedProminent)
                } else if model.isBusy {
                    ProgressView().controlSize(.small)
                } else if can(.wakeOnLAN) {
                    Button("Turn the TV on") { model.turnOn() }.buttonStyle(.borderedProminent)
                }
                if !model.isBusy {
                    Button("Try again") { Task { await model.reconnect() } }
                }
            }
        }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TV address").font(.subheadline.weight(.semibold)).foregroundStyle(Remote.label)
            TextField("192.168.0.10", text: $draftHost)
                .textFieldStyle(.roundedBorder)
                .onSubmit(saveSettings)
            Text(brand.addressHelp)
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

    private func can(_ capability: TVCapabilities) -> Bool {
        brand.supports(capability)
    }

    private func key(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
        }
        .buttonStyle(KeyStyle(shape: .circle, size: CGSize(width: 30, height: 30), fill: Remote.key))
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
        case .idle: return brand.displayName
        case .connecting: return "Connecting…"
        case .pairing: return "Waiting for the TV"
        case .connected: return "TV is on"
        case .unreachable: return "TV is off or out of reach"
        case .networkBlocked: return "Local Network access needed"
        }
    }

    private var offlineText: String {
        if model.isWaking && model.status != .pairing { return "Turning the TV on. This takes about 10 seconds." }
        switch model.status {
        case .pairing:
            return "The TV is asking whether to allow this Mac. Accept it with the TV remote."
        case .connecting:
            return "Connecting to the TV at \(model.host)."
        case .networkBlocked:
            return "macOS blocks RemoteTV from your local network. Turn on RemoteTV under Privacy & Security > Local Network, then try again."
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

/// The remote's materials: a graphite body, slightly lighter keys, a red power key.
private enum Remote {
    static let body = Color(red: 0.11, green: 0.11, blue: 0.13)
    static let key = Color(red: 0.19, green: 0.19, blue: 0.22)
    static let okKey = Color(red: 0.27, green: 0.27, blue: 0.31)
    static let edge = Color.white.opacity(0.08)
    static let label = Color(red: 0.92, green: 0.92, blue: 0.94)
    static let power = Color(red: 0.82, green: 0.15, blue: 0.17)
    static let powerArmed = Color(red: 0.95, green: 0.25, blue: 0.20)
    static let active = Color.accentColor
}

/// A physical key: a raised shape that sinks a little when pressed.
private struct KeyStyle: ButtonStyle {
    /// A circle key has a fixed square size; a capsule key stretches to its width.
    /// Both draw a `Capsule`, which is a circle in a square frame.
    enum Shape { case circle, capsule }
    let shape: Shape
    let size: CGSize
    /// Nil for keys drawn on another key's surface, such as the wheel's arrows.
    let fill: Color?

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Remote.label)
            .frame(minWidth: size.width, maxWidth: shape == .capsule ? .infinity : size.width)
            .frame(height: size.height)
            .background {
                if let fill {
                    Capsule().fill(fill)
                        .overlay(Capsule().strokeBorder(Remote.edge, lineWidth: 1))
                        .shadow(color: .black.opacity(configuration.isPressed ? 0 : 0.5), radius: 2, y: configuration.isPressed ? 0 : 2)
                }
            }
            .contentShape(Capsule())
            .brightness(configuration.isPressed ? 0.12 : 0)
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

/// One half of a rocker: the whole half is the hit area, and it lights up when pressed.
private struct RockerHalfStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Remote.label)
            .background(Color.white.opacity(configuration.isPressed ? 0.12 : 0))
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}
