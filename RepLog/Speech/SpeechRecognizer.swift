import Foundation
import Speech
import AVFoundation
import Observation

/// Live speech-to-text with silence auto-stop: tap, talk, and ~2s of quiet
/// finishes the utterance and hands the transcript to `onFinish`.
@Observable
@MainActor
final class SpeechRecognizer {
    var transcript = ""
    var isRecording = false
    var errorMessage: String?
    var onFinish: ((String) -> Void)?
    /// Domain words (exercise names, gym jargon) the recognizer should favor.
    var vocabulary: [String] = []

    private var audioEngine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var lastChange = Date()
    private var silenceMonitor: Task<Void, Never>?

    private static let silenceCutoff: TimeInterval = 2.0
    private static let maxDuration: TimeInterval = 90

    func toggle() {
        if isRecording {
            finish()
        } else {
            Task { await start() }
        }
    }

    private func start() async {
        errorMessage = nil
        transcript = ""

        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speechStatus == .authorized else {
            errorMessage = "Speech recognition not allowed. Enable it in iOS Settings → RepLog."
            return
        }
        let micAllowed = await AVAudioApplication.requestRecordPermission()
        guard micAllowed else {
            errorMessage = "Microphone access not allowed. Enable it in iOS Settings → RepLog."
            return
        }
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
            errorMessage = "Speech recognition is unavailable on this device right now."
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let engine = AVAudioEngine()
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.contextualStrings = vocabulary

            let inputNode = engine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }
            engine.prepare()
            try engine.start()

            self.audioEngine = engine
            self.request = request
            self.lastChange = Date()
            self.isRecording = true

            self.task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor [weak self] in
                    guard let self, self.isRecording else { return }
                    if let result {
                        self.transcript = result.bestTranscription.formattedString
                        self.lastChange = Date()
                    }
                    if error != nil || (result?.isFinal ?? false) {
                        self.finish()
                    }
                }
            }
            startSilenceMonitor()
        } catch {
            errorMessage = "Could not start recording: \(error.localizedDescription)"
            cleanup()
        }
    }

    private func startSilenceMonitor() {
        let startedAt = Date()
        silenceMonitor = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self, await self.isRecording else { return }
                let idle = await Date().timeIntervalSince(self.lastChange)
                let heardSomething = await !self.transcript.isEmpty
                let ranTooLong = Date().timeIntervalSince(startedAt) > Self.maxDuration
                if (heardSomething && idle > Self.silenceCutoff) || ranTooLong {
                    await self.finish()
                    return
                }
            }
        }
    }

    private func finish() {
        guard isRecording else { return }
        isRecording = false
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        cleanup()
        if !text.isEmpty {
            onFinish?(text)
        }
        transcript = ""
    }

    private func cleanup() {
        silenceMonitor?.cancel()
        silenceMonitor = nil
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isRecording = false
    }
}
