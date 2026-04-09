import Speech
import AVFoundation
import Combine

@MainActor
final class SpeechManager: ObservableObject {
    static let shared = SpeechManager()

    @Published var isRecording = false
    @Published var isAuthorized = false
    @Published var audioLevel: Float = 0   // 0–1, drives waveform UI
    @Published var errorMessage: String?

    private var recognizer: SFSpeechRecognizer?
    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var activeSessionID: UUID?

    private init() {
        recognizer = SFSpeechRecognizer(locale: .current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en_US"))
    }

    func startRecording(onPartial: @escaping (String) -> Void, onFinal: @escaping (String) -> Void) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let hasPermissions = await self.ensurePermissions()
            guard hasPermissions else { return }
            guard let recognizer = self.recognizer else {
                self.errorMessage = "Speech recognizer is unavailable for the current locale."
                return
            }
            guard recognizer.isAvailable else {
                self.errorMessage = "Speech recognizer is currently unavailable."
                return
            }
            self.doStartRecording(onPartial: onPartial, onFinal: onFinal)
        }
    }

    private func ensurePermissions() async -> Bool {
        let speechGranted = await ensureSpeechAuthorization()
        let micGranted = await ensureMicrophoneAuthorization()
        isAuthorized = speechGranted && micGranted
        if !speechGranted {
            errorMessage = "Speech recognition access is denied. Open System Settings > Privacy & Security > Speech Recognition."
            return false
        }
        if !micGranted {
            errorMessage = "Microphone access is denied. Open System Settings > Privacy & Security > Microphone."
            return false
        }
        return true
    }

    private func ensureSpeechAuthorization() async -> Bool {
        let current = SFSpeechRecognizer.authorizationStatus()
        if current == .authorized { return true }
        if current == .denied || current == .restricted { return false }
        return await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
    }

    private func ensureMicrophoneAuthorization() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        if status == .authorized { return true }
        if status == .denied || status == .restricted { return false }
        return await withCheckedContinuation { cont in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                cont.resume(returning: granted)
            }
        }
    }

    private func doStartRecording(onPartial: @escaping (String) -> Void, onFinal: @escaping (String) -> Void) {
        guard let recognizer, recognizer.isAvailable else {
            errorMessage = "Speech recognizer is currently unavailable."
            return
        }
        stopRecording()
        errorMessage = nil
        let sessionID = UUID()
        activeSessionID = sessionID

        // Fresh engine every session — avoids tap-already-installed crashes
        let engine = AVAudioEngine()
        audioEngine = engine

        let request = SFSpeechAudioBufferRecognitionRequest()
        recognitionRequest = request
        request.shouldReportPartialResults = true
        // Keep mic on for up to 60 s without a final result
        if #available(macOS 13, *) {
            request.addsPunctuation = true
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            guard self.activeSessionID == sessionID else { return }
            if let result {
                let text = result.bestTranscription.formattedString
                Task { @MainActor in
                    guard self.activeSessionID == sessionID else { return }
                    onPartial(text)
                    if result.isFinal {
                        onFinal(text)
                        self.stopRecording()
                    }
                }
            } else if let error {
                let nsError = error as NSError
                Task { @MainActor in
                    guard self.activeSessionID == sessionID else { return }
                    // 301 is commonly returned when the session is interrupted/cancelled
                    // or no usable speech is captured; treat it as a user-facing prompt.
                    if nsError.code == 301 {
                        self.errorMessage = "No speech captured. Speak right after tapping the mic and try again."
                    } else {
                        self.errorMessage = "Speech recognition failed (\(nsError.code)). Try again and confirm permissions in System Settings."
                    }
                    self.stopRecording()
                }
            }
        }

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self, weak request] buffer, _ in
            request?.append(buffer)
            // Compute RMS for the waveform bar heights
            guard let data = buffer.floatChannelData?[0] else { return }
            let frames = Int(buffer.frameLength)
            guard frames > 0 else { return }
            var rms: Float = 0
            for i in 0..<frames { rms += data[i] * data[i] }
            rms = sqrt(rms / Float(frames))
            let level = min(rms * 40, 1.0)
            Task { @MainActor [weak self] in self?.audioLevel = level }
        }

        do {
            engine.prepare()
            try engine.start()
            isRecording = true
        } catch {
            let nsError = error as NSError
            errorMessage = "Could not start microphone recording (\(nsError.code))."
            stopRecording()
        }
    }

    func stopRecording() {
        activeSessionID = nil
        audioLevel = 0
        isRecording = false
        if let engine = audioEngine {
            if engine.isRunning {
                engine.stop()
            }
            // removeTap is safe to call even if no tap is installed
            engine.inputNode.removeTap(onBus: 0)
        }
        audioEngine = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
    }
}
