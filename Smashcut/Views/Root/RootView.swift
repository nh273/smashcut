import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        NavigationStack {
            ProjectListView()
                .navigationTitle("Smashcut")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            appState.isSettingsPresented = true
                        } label: {
                            Image(systemName: "gear")
                        }
                    }
                }
        }
        .sheet(isPresented: $appState.isSettingsPresented) {
            SettingsView()
        }
        .sheet(isPresented: .constant(!appState.hasAPIKey)) {
            APIKeySetupView()
        }
    }
}
