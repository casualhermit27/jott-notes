import Speech
import AVFoundation
import Combine

@MainActor
final class SpeechManager: ObservableObject {
    static let shared = SpeechManager()

    @Published var isRecording = false
    @Published var isAuthorized = false
    @Published var audioLevel: Float = 0   // 0–1, drives waveform UI

    private let recognizer: SFSpeechRecognizer?
    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    private init() {
        recognizer = SFSpeechRecognizer(locale: .current)
        requestPermissions()
    }

    private func requestPermissions() {
        // Must request mic access explicitly on macOS before AVAudioEngine will work
        AVCaptureDevice.requestAccess(for: .audio) { _ in }
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor [weak self] in
                self?.isAuthorized = status == .authorized
            }
        }
    }

    func startRecording(onPartial: @escaping (String) -> Void, onFinal: @escaping (String) -> Void) {
        // Ensure mic permission is granted before touching the audio engine
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            guard granted else { return }
            Task { @MainActor [weak self] in
                self?.doStartRecording(onPartial: onPartial, onFinal: onFinal)
            }
        }
    }

    private func doStartRecording(onPartial: @escaping (String) -> Void, onFinal: @escaping (String) -> Void) {
        guard let recognizer, recognizer.isAvailable else { return }
        stopRecording()

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
            if let result {
                let text = result.bestTranscription.formattedString
                Task { @MainActor in
                    onPartial(text)
                    if result.isFinal {
                        onFinal(text)
                        self.stopRecording()
                    }
                }
            } else if error != nil {
                Task { @MainActor in self.stopRecording() }
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
            stopRecording()
        }
    }

    func stopRecording() {
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
