import SwiftUI

@main
struct SmashcutApp: App {
    @State private var appState = AppState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                Task {
                    await LayerAssetCache.shared.evictIfNeeded()
                }
            }
        }
    }
}
