import PhotosUI
import SwiftUI

struct BackgroundEditorView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let section: ScriptSection
    let project: Project

    @State private var vm: BackgroundEditorViewModel
    @State private var showingMediaPicker = false
    @State private var pickerResult: PhotosPickerItem?

    init(section: ScriptSection, project: Project) {
        self.section = section
        self.project = project
        _vm = State(initialValue: BackgroundEditorViewModel(section: section, projectID: project.id))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                sectionPreview

                backgroundPicker

                if vm.section.recording?.backgroundMediaURL != nil || vm.backgroundImage != nil {
                    processButton
                }

                if vm.isProcessing {
                    processingProgress
                }

                if let error = vm.processingError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding()
        }
        .navigationTitle("Background Editor")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingMediaPicker) {
            PhotosPicker(
                selection: $pickerResult,
                matching: .any(of: [.images, .videos])
            ) {
                Text("Choose Media")
            }
        }
        .onChange(of: pickerResult) { _, newItem in
            vm.selectedItem = newItem
            Task { await vm.loadSelectedMedia() }
        }
        .onChange(of: vm.processingComplete) { _, done in
            if done { saveAndDismiss() }
        }
    }

    private var sectionPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Section \(section.index + 1)")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Text(section.text)
                .font(.body)
                .padding()
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private var backgroundPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Background Media")
                .font(.headline)

            if let image = vm.backgroundImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(alignment: .topTrailing) {
                        Button {
                            vm.backgroundImage = nil
                            if var rec = vm.section.recording {
                                rec.backgroundMediaURL = nil
                                vm.section.recording = rec
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.white)
                                .background(Color.black.opacity(0.5), in: Circle())
                        }
                        .padding(8)
                    }
            } else if vm.backgroundVideoURL != nil {
                HStack {
                    Image(systemName: "video.fill")
                    Text("Video background selected")
                    Spacer()
                    Button {
                        vm.backgroundVideoURL = nil
                        if var rec = vm.section.recording {
                            rec.backgroundMediaURL = nil
                            vm.section.recording = rec
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                PhotosPicker(selection: $pickerResult, matching: .any(of: [.images, .videos])) {
                    Label("Choose Photo or Video", systemImage: "photo.on.rectangle.angled")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            if vm.backgroundImage != nil || vm.backgroundVideoURL != nil {
                PhotosPicker(selection: $pickerResult, matching: .any(of: [.images, .videos])) {
                    Label("Change Background", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption)
                }
            }
        }
    }

    private var processButton: some View {
        Button {
            Task { await vm.processBackground() }
        } label: {
            Label("Remove Background & Process", systemImage: "person.and.background.dotted")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(vm.isProcessing)
    }

    private var processingProgress: some View {
        VStack(spacing: 8) {
            ProgressView(value: vm.processingProgress)
            HStack {
                Text("Processing…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(vm.processingProgress * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text("Background removal takes 60-90 seconds on a 30s clip.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func saveAndDismiss() {
        var updated = project
        if var script = updated.script {
            if let idx = script.sections.firstIndex(where: { $0.id == section.id }) {
                script.sections[idx] = vm.section
            }
            updated.script = script
        }
        appState.updateProject(updated)
        dismiss()
    }
}
