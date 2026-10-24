import RemoteTVCore
import SwiftUI

/// Power on the left and Input on the right, where a TV remote has them.
struct HeaderBar: View {
    let model: RemoteModel

    var body: some View {
        HStack(spacing: 8) {
            if model.status == .connected {
                if brand.supports(.powerOff) { PowerKey(model: model) }
                if brand.supports(.screenOff) { ScreenKey(model: model) }
            }
            Circle().fill(statusColor).frame(width: 6, height: 6)
            Text(statusText).font(.caption.weight(.medium)).foregroundStyle(RemotePalette.label)
            Spacer()
            if model.status == .connected && brand.supports(.inputs) { InputMenu(model: model) }
        }
    }

    private var statusText: String {
        switch model.status {
        case .idle: brand.displayName
        case .connecting: "Connecting…"
        case .pairing: "Waiting for the TV"
        case .connected: "TV is on"
        case .unreachable: "TV is off or out of reach"
        case .networkBlocked: "Local Network access needed"
        }
    }

    private var statusColor: Color {
        switch model.status {
        case .connected: .green
        case .connecting, .pairing: .orange
        case .networkBlocked: .red
        case .idle, .unreachable: .gray
        }
    }
}
