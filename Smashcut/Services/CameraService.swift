import AVFoundation
import Observation

@Observable
class CameraService: NSObject {
    var session = AVCaptureSession()
    var isAuthorized = false
    var authorizationError: String?
    var isConfigured = false

    private var videoInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?

    func checkAndRequestPermissions() async {
        let videoStatus = AVCaptureDevice.authorizationStatus(for: .video)
        let audioStatus = AVCaptureDevice.authorizationStatus(for: .audio)

        var videoGranted = videoStatus == .authorized
        var audioGranted = audioStatus == .authorized

        if videoStatus == .notDetermined {
            videoGranted = await AVCaptureDevice.requestAccess(for: .video)
        }
        if audioStatus == .notDetermined {
            audioGranted = await AVCaptureDevice.requestAccess(for: .audio)
        }

        await MainActor.run {
            if videoGranted && audioGranted {
                self.isAuthorized = true
                self.configureSession()
            } else {
                self.authorizationError = "Camera and microphone access are required to record narration."
            }
        }
    }

    private func configureSession() {
        guard !isConfigured else { return }
        session.beginConfiguration()
        session.sessionPreset = .hd1920x1080

        guard let frontCamera = AVCaptureDevice.default(
            .builtInWideAngleCamera, for: .video, position: .front
        ) else {
            session.commitConfiguration()
            return
        }

        do {
            let vi = try AVCaptureDeviceInput(device: frontCamera)
            if session.canAddInput(vi) {
                session.addInput(vi)
                videoInput = vi
            }

            if let mic = AVCaptureDevice.default(for: .audio) {
                let ai = try AVCaptureDeviceInput(device: mic)
                if session.canAddInput(ai) {
                    session.addInput(ai)
                    audioInput = ai
                }
            }
        } catch {
            authorizationError = "Camera setup failed: \(error.localizedDescription)"
        }

        session.commitConfiguration()
        isConfigured = true
    }

    func startSession() {
        guard isAuthorized, !session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
        }
    }

    func stopSession() {
        guard session.isRunning else { return }
        session.stopRunning()
    }
}
