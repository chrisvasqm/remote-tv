import RemoteTVCore
import SwiftUI

/// The TV address and unpairing.
struct SettingsPanel: View {
    let model: RemoteModel
    @Binding var isShown: Bool
    @Binding var draftHost: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TV address").font(.subheadline.weight(.semibold)).foregroundStyle(RemotePalette.label)
            TextField("192.168.0.10", text: $draftHost)
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)
            Text(brand.addressHelp)
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Connect", action: save)
                    .buttonStyle(.borderedProminent)
                    .disabled(draftHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Spacer()
                Button("Unpair this Mac", role: .destructive, action: model.forgetPairing)
                    .help("Remove the saved pairing. The TV asks again next time.")
            }
        }
    }

    private func save() {
        isShown = false
        Task { await model.setHost(draftHost) }
    }
}
