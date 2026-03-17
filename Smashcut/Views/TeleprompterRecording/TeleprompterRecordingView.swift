import AVFoundation
import SwiftUI

struct TeleprompterRecordingView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let section: ScriptSection
    let project: Project

    @State private var vm: TeleprompterRecordingViewModel
    @State private var dragOffset: CGFloat = 0

    init(section: ScriptSection, project: Project) {
        self.section = section
        self.project = project
        _vm = State(initialValue: TeleprompterRecordingViewModel(
            section: section,
            projectID: project.id
        ))
    }

    var body: some View {
        ZStack {
            // Camera preview (full screen)
            if vm.cameraService.isAuthorized {
                CameraPreviewView(session: vm.cameraService.session)
                    .ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
                if let err = vm.cameraService.authorizationError {
                    VStack(spacing: 16) {
                        Image(systemName: "camera.slash")
                            .font(.system(size: 48))
                            .foregroundStyle(.white)
                        Text(err)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .padding()
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }

            // Teleprompter overlay (top half, semi-transparent)
            VStack {
                ZStack {
                    Color.black.opacity(0.55)
                        .ignoresSafeArea(edges: .top)
                    TeleprompterOverlayView(
                        words: vm.words,
                        currentWordIndex: vm.currentWordIndex,
                        isRecording: vm.isRecording
                    )
                }
                .frame(maxHeight: UIScreen.main.bounds.height * 0.55)

                Spacer()

                // Controls
                HStack(spacing: 32) {
                    closeButton

                    recordButton

                    if vm.isRecording {
                        Text(elapsedTimeString)
                            .font(.system(.title3, design: .monospaced).bold())
                            .foregroundStyle(.white)
                            .frame(width: 80)
                    } else {
                        Spacer().frame(width: 80)
                    }
                }
                .padding(.bottom, 48)
            }
        }
        .offset(y: dragOffset)
        .gesture(swipeDownToDismiss)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    closeTeleprompter()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task {
            await vm.setup()
        }
        .onChange(of: vm.recordingFinished) { _, finished in
            if finished {
                saveAndDismiss()
            }
        }
        .alert("Error", isPresented: .constant(vm.error != nil)) {
            Button("OK") { vm.error = nil }
        } message: {
            Text(vm.error ?? "")
        }
    }

    private var closeButton: some View {
        Button {
            closeTeleprompter()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 72, height: 72)
                .contentShape(Rectangle())
        }
    }

    private func closeTeleprompter() {
        vm.teardown()
        dismiss()
    }

    private var swipeDownToDismiss: some Gesture {
        DragGesture()
            .onChanged { value in
                if value.translation.height > 0 {
                    dragOffset = value.translation.height
                }
            }
            .onEnded { value in
                if value.translation.height > 120 {
                    closeTeleprompter()
                } else {
                    withAnimation(.easeOut(duration: 0.2)) {
                        dragOffset = 0
                    }
                }
            }
    }

    private var recordButton: some View {
        Button {
            if vm.isRecording {
                vm.stopRecording()
            } else {
                vm.startRecording()
            }
        } label: {
            ZStack {
                Circle()
                    .stroke(Color.white, lineWidth: 4)
                    .frame(width: 72, height: 72)
                if vm.isRecording {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.red)
                        .frame(width: 28, height: 28)
                } else {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 56, height: 56)
                }
            }
        }
    }

    private var elapsedTimeString: String {
        let elapsed = vm.recordingStartTime.map { -$0.timeIntervalSinceNow } ?? 0
        let minutes = Int(elapsed) / 60
        let seconds = Int(elapsed) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func saveAndDismiss() {
        var updated = project
        // Legacy write
        if var script = updated.script {
            if let idx = script.sections.firstIndex(where: { $0.id == section.id }) {
                script.sections[idx] = vm.section
            }
            updated.script = script
        }
        // Dual-write: update SectionEdit media bin
        if var edits = updated.sectionEdits,
           let idx = edits.firstIndex(where: { $0.id == section.id }),
           let recording = vm.section.recording {
            SectionEditBridge.addVideo(
                to: &edits[idx],
                url: recording.rawVideoURL,
                duration: recording.durationSeconds,
                captionTimestamps: recording.captionTimestamps
            )
            updated.sectionEdits = edits
        }
        appState.updateProject(updated)
        dismiss()
    }
}

