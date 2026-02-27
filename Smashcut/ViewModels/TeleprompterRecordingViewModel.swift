import AVFoundation
import Combine
import Foundation
import Observation

@Observable
class TeleprompterRecordingViewModel {
    var section: ScriptSection
    var projectID: UUID

    var isRecording = false
    var recordingFinished = false
    var error: String?
    var elapsedSeconds: Double = 0

    var captionTimestamps: [CaptionTimestamp] = []
    var currentWordIndex: Int = 0
    var words: [String] = []

    var recordingStartTime: Date?
    private var scrollTimer: Timer?
    private let wordsPerMinute: Double = 130

    let cameraService = CameraService()
    let recordingService = RecordingService()

    init(section: ScriptSection, projectID: UUID) {
        self.section = section
        self.projectID = projectID
        self.words = section.text
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
    }

    func setup() async {
        await cameraService.checkAndRequestPermissions()
        if cameraService.isAuthorized {
            recordingService.addOutput(to: cameraService.session)
            cameraService.startSession()
        }
    }

    func startRecording() {
        let outputURL = VideoFileManager.rawVideoURL(projectID: projectID, sectionID: section.id)
        recordingService.startRecording(to: outputURL)
        recordingStartTime = Date()
        isRecording = true
        captionTimestamps = []
        currentWordIndex = 0
        startTeleprompter()
    }

    func stopRecording() {
        scrollTimer?.invalidate()
        scrollTimer = nil
        let duration = -(recordingStartTime?.timeIntervalSinceNow ?? 0)
        elapsedSeconds = duration

        recordingService.stopRecording { [weak self] url in
            guard let self, let url else {
                self?.error = "Recording failed"
                return
            }
            var recording = Recording(
                sectionID: self.section.id,
                rawVideoURL: url
            )
            recording.captionTimestamps = self.captionTimestamps
            recording.durationSeconds = self.elapsedSeconds
            self.section.recording = recording
            self.section.status = .recorded
            self.isRecording = false
            self.recordingFinished = true
        }
    }

    private func startTeleprompter() {
        let secondsPerWord = 60.0 / wordsPerMinute
        var wordIndex = 0

        scrollTimer = Timer.scheduledTimer(withTimeInterval: secondsPerWord, repeats: true) { [weak self] _ in
            guard let self, wordIndex < self.words.count else {
                self?.scrollTimer?.invalidate()
                return
            }
            let elapsed = -(self.recordingStartTime?.timeIntervalSinceNow ?? 0)
            let word = self.words[wordIndex]
            let timestamp = CaptionTimestamp(
                text: word,
                startSeconds: elapsed,
                endSeconds: elapsed + secondsPerWord
            )
            self.captionTimestamps.append(timestamp)
            self.currentWordIndex = wordIndex
            wordIndex += 1
        }
    }

    func teardown() {
        scrollTimer?.invalidate()
        cameraService.stopSession()
    }
}
