import AVFoundation
import Foundation
import Observation

@Observable
class RecordingService: NSObject {
    var isRecording = false
    var recordingError: String?

    private var fileOutput: AVCaptureMovieFileOutput?
    private var completionHandler: ((URL?) -> Void)?

    func addOutput(to session: AVCaptureSession) {
        let output = AVCaptureMovieFileOutput()
        if session.canAddOutput(output) {
            session.addOutput(output)
            fileOutput = output
        }
    }

    func startRecording(to url: URL) {
        guard let fileOutput, !fileOutput.isRecording else { return }
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: url)
        fileOutput.startRecording(to: url, recordingDelegate: self)
        isRecording = true
    }

    func stopRecording(completion: @escaping (URL?) -> Void) {
        guard let fileOutput, fileOutput.isRecording else {
            completion(nil)
            return
        }
        completionHandler = completion
        fileOutput.stopRecording()
    }
}

extension RecordingService: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        DispatchQueue.main.async { [weak self] in
            self?.isRecording = false
            if let error {
                self?.recordingError = error.localizedDescription
                self?.completionHandler?(nil)
            } else {
                self?.completionHandler?(outputFileURL)
            }
            self?.completionHandler = nil
        }
    }
}
