import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var apiKey: String = ""
    @State private var showSaved = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    SecureField("sk-ant-...", text: $apiKey)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("Anthropic API Key")
                } footer: {
                    Text("Get your key at console.anthropic.com")
                }

                Section {
                    Button("Save API Key") {
                        KeychainService.shared.saveAPIKey(apiKey)
                        showSaved = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            dismiss()
                        }
                    }
                    .disabled(apiKey.isEmpty)

                    if appState.hasAPIKey {
                        Button("Remove API Key", role: .destructive) {
                            KeychainService.shared.deleteAPIKey()
                            apiKey = ""
                        }
                    }
                }

                if showSaved {
                    Section {
                        Label("API key saved!", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                if let key = KeychainService.shared.retrieveAPIKey() {
                    apiKey = key
                }
            }
        }
    }
}
