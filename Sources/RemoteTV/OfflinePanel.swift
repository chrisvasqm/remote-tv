import RemoteTVCore
import SwiftUI

/// Shown while the TV is not connected: what is happening, and what to do.
struct OfflinePanel: View {
    let model: RemoteModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text)
                .font(.callout).foregroundStyle(RemotePalette.label)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                if model.status == .networkBlocked {
                    Button("Open Local Network settings", action: LocalNetworkAccess.openSettings)
                        .buttonStyle(.borderedProminent)
                } else if model.isBusy {
                    ProgressView().controlSize(.small)
                } else if brand.supports(.wakeOnLAN) {
                    Button("Turn the TV on", action: model.turnOn).buttonStyle(.borderedProminent)
                }
                if !model.isBusy {
                    Button("Try again", action: reconnect)
                }
            }
        }
    }

    private func reconnect() {
        model.reconnect()
    }

    private var text: String {
        if model.isWaking && model.status != .pairing { return "Turning the TV on. This takes about 10 seconds." }
        return switch model.status {
        case .pairing:
            "The TV is asking whether to allow this Mac. Accept it with the TV remote."
        case .connecting:
            "Connecting to the TV at \(model.host)."
        case .networkBlocked:
            "macOS blocks RemoteTV from your local network. "
                + "Turn on RemoteTV under Privacy & Security > Local Network, then try again."
        default:
            "Can't reach the TV at \(model.host). If it is off, turn it on here. "
                + "Otherwise check that the Mac and the TV are on the same Wi-Fi."
        }
    }
}
