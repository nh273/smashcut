import SwiftUI

/// Consistent auto-save status indicator used across all editor screens.
struct SaveStatusView: View {
    let isSaving: Bool

    var body: some View {
        HStack(spacing: 4) {
            if isSaving {
                ProgressView()
                    .controlSize(.mini)
                Text("Saving…")
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Saved")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .animation(.easeInOut(duration: 0.2), value: isSaving)
    }
}
