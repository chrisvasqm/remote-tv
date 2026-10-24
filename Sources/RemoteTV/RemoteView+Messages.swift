import RemoteTVCore
import SwiftUI

extension RemoteView {
    private static let presets = ["Bedtime in 10 min", "Dinner is ready", "Screen time is over"]

    // MARK: - Messages

    var messages: some View {
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

    private var trimmedMessage: String { message.trimmingCharacters(in: .whitespaces) }

    private func sendMessage() {
        guard !trimmedMessage.isEmpty else { return }
        model.showMessage(trimmedMessage)
        message = ""
    }
}
