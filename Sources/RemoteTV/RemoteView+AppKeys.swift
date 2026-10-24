import RemoteTVCore
import SwiftUI

extension RemoteView {
    // MARK: - Apps

    /// The app shortcut keys at the bottom of the remote, three to a row.
    /// A short last row is centred, the way keys sit on a remote.
    var appKeys: some View {
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
}
