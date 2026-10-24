import RemoteTVCore
import SwiftUI

extension RemoteView {
    // MARK: - Offline and settings

    var offline: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(offlineText).font(.callout).foregroundStyle(RemotePalette.label).fixedSize(horizontal: false, vertical: true)
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

    var settings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TV address").font(.subheadline.weight(.semibold)).foregroundStyle(RemotePalette.label)
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

    private func saveSettings() {
        showSettings = false
        Task { await model.setHost(draftHost) }
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
}
