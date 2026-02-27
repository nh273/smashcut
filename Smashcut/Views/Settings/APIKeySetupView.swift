import SwiftUI

struct APIKeySetupView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var apiKey: String = ""

    var body: some View {
        VStack(spacing: 32) {
            VStack(spacing: 12) {
                Image(systemName: "key.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Color.accentColor)
                Text("Welcome to Smashcut")
                    .font(.largeTitle.bold())
                Text("Enter your Anthropic API key to use AI script refinement.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 48)

            VStack(alignment: .leading, spacing: 8) {
                Text("API Key")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                SecureField("sk-ant-...", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                Link("Get your key at console.anthropic.com",
                     destination: URL(string: "https://console.anthropic.com")!)
                    .font(.caption)
            }
            .padding(.horizontal, 32)

            VStack(spacing: 12) {
                Button {
                    appState.saveAPIKey(apiKey)
                    dismiss()
                } label: {
                    Text("Continue")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(apiKey.isEmpty)
                .padding(.horizontal, 32)

                Button("Skip for now") {
                    dismiss()
                }
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .interactiveDismissDisabled(true)
    }
}
