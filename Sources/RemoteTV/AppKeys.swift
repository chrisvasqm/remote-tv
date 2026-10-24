import RemoteTVCore
import SwiftUI

/// The app shortcut keys at the bottom of the remote, three to a row.
/// A short last row is centred, the way keys sit on a remote.
struct AppKeys: View {
    let model: RemoteModel
    private static let columns = 3
    private static let spacing: CGFloat = 5
    private static let width = (PanelMetrics.previewWidth - spacing * CGFloat(columns - 1)) / CGFloat(columns)

    var body: some View {
        VStack(spacing: Self.spacing) {
            ForEach(rows, id: \.first?.id) { row in
                HStack(spacing: Self.spacing) {
                    ForEach(row) { app in
                        Button { model.launch(app) } label: {
                            Text(app.title).font(.caption2.weight(.semibold))
                                .lineLimit(1).minimumScaleFactor(0.8).padding(.horizontal, 4)
                        }
                        .buttonStyle(KeyStyle(
                            shape: .capsule, size: CGSize(width: Self.width, height: 22),
                            fill: app.id == model.foregroundAppId ? RemotePalette.active : RemotePalette.key
                        ))
                        .frame(width: Self.width)
                    }
                }
            }
        }
    }

    private var rows: [[TVApp]] {
        let apps = model.apps
        return stride(from: 0, to: apps.count, by: Self.columns).map {
            Array(apps[$0..<min($0 + Self.columns, apps.count)])
        }
    }
}
