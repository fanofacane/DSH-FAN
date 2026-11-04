// SPDX-License-Identifier: AGPL-3.0-or-later
// Dictation into the composer with the Speech framework: live partial text,
// on-device when the language supports it, stops on tap, silence or the
// recognizer's own limit.
import AVFoundation
import Observation
import Speech

@MainActor
@Observable
final class VoiceInput {
    enum State: Equatable { case idle, starting, listening, denied, unavailable }

    private(set) var state = State.idle
    /// 0…1 microphone level for the meter.
    private(set) var level: Float = 0

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private var silence: Task<Void, Never>?
    @ObservationIgnored private var onText: ((String) -> Void)?

    @ObservationIgnored private var session: AVAudioSession?

    var isActive: Bool { state == .starting || state == .listening }

    /// Starts dictation; `onText` receives the whole utterance so far.
    func start(session: AVAudioSession, onText: @escaping (String) -> Void) async {
        guard !isActive else { return }
        state = .starting
        guard await Self.authorize() else { state = .denied; return }
        let recognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer()
        guard let recognizer, recognizer.isAvailable else { state = .unavailable; return }
        do {
            self.session = session
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.addsPunctuation = true
            if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                request.append(buffer)
                let level = Self.level(buffer)
                Task { @MainActor in self?.level = level }
            }
            engine.prepare()
            try engine.start()
            self.request = request
            self.onText = onText
            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                let text = result?.bestTranscription.formattedString
                let done = error != nil || result?.isFinal == true
                Task { @MainActor in
                    guard let self, self.isActive else { return }
                    if let text { self.onText?(text); self.armSilence() }
                    if done { self.finish() }
                }
            }
            state = .listening
            armSilence()
        } catch {
            finish()
            state = .unavailable
        }
    }

    /// Stops listening; the recognizer delivers the final text first.
    func stop() {
        guard isActive else { return }
        request?.endAudio()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            self.finish()
        }
    }

    /// Ends after 3 s without new words.
    private func armSilence() {
        silence?.cancel()
        silence = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            self?.stop()
        }
    }

    private func finish() {
        silence?.cancel(); silence = nil
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        task?.cancel(); task = nil
        request = nil; onText = nil
        level = 0
        if state == .starting || state == .listening { state = .idle }
        try? session?.setActive(false, options: .notifyOthersOnDeactivation)
    }

    func resetMessage() { if state == .denied || state == .unavailable { state = .idle } }

    private static func authorize() async -> Bool {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
        guard speech else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }

    nonisolated private static func level(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<Int(buffer.frameLength) { sum += samples[i] * samples[i] }
        let rms = (sum / Float(buffer.frameLength)).squareRoot()
        return min(1, max(0, (20 * log10(max(rms, 1e-6)) + 50) / 50))
    }
}
