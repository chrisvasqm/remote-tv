import SwiftUI

/// Shows a short message on the TV: a few presets, or any text.
struct MessagesPanel: View {
    let model: RemoteModel
    @State private var message = ""
    private static let presets = ["Bedtime in 10 min", "Dinner is ready", "Screen time is over"]

    var body: some View {
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
                    .onSubmit(send)
                Button("Show", action: send).disabled(trimmedMessage.isEmpty)
            }
            if let sent = model.lastMessageSent {
                Label("Shown on the TV: \(sent)", systemImage: "checkmark.circle")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .font(.callout)
        .foregroundStyle(RemotePalette.label)
    }

    private var trimmedMessage: String { message.trimmingCharacters(in: .whitespaces) }

    private func send() {
        guard !trimmedMessage.isEmpty else { return }
        model.showMessage(trimmedMessage)
        message = ""
    }
}
