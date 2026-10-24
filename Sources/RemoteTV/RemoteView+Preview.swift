import RemoteTVCore
import SwiftUI

extension RemoteView {
    // MARK: - Live screen

    var screen: some View {
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
}
