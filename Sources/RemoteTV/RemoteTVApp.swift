import SwiftUI

@main
struct RemoteTVApp: App {
    @State private var model = RemoteModel()

    var body: some Scene {
        MenuBarExtra {
            RemoteView(model: model)
        } label: {
            Image(systemName: model.status == .connected ? "tv.fill" : "tv")
        }
        .menuBarExtraStyle(.window)
    }
}
