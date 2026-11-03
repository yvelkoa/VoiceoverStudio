import AVFoundation
import Speech
import VoiceoverKit

/// Turns a recorded take into timed words for captions.
///
/// Uses the on-device `SpeechTranscriber` where the language is supported (English and a dozen others);
/// for the rest, including Russian and Ukrainian, falls back to `SFSpeechRecognizer`, which may use
/// Apple's servers and is limited to about a minute of audio per request.
nonisolated enum Transcriber {
    enum Failure: LocalizedError {
        case notAuthorized, unavailable(Locale)

        var errorDescription: String? {
            switch self {
            case .notAuthorized: return "Speech recognition is off. Allow it in Settings to get captions."
            case .unavailable(let locale):
                let name = locale.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
                return "Speech recognition isn't available for \(name)."
            }
        }
    }

    /// Words in `file`, with times relative to the start of the file.
    @concurrent
    static func words(in file: URL, locale: Locale) async throws -> [TimedWord] {
        if let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) {
            return try await onDeviceWords(in: file, locale: supported)
        }
        return try await legacyWords(in: file, locale: locale)
    }

    // MARK: - iOS 26 SpeechAnalyzer

    private static func onDeviceWords(in file: URL, locale: Locale) async throws -> [TimedWord] {
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: [.audioTimeRange]
        )
        // The app has to hold a reservation for the locale before it may query or download its model;
        // without it the install request fails with "not subscribed to transcription.<lang>".
        if await !AssetInventory.reservedLocales.contains(locale) {
            _ = try await AssetInventory.reserve(locale: locale)
        }
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }

        let audioFile = try AVAudioFile(forReading: file)
        let analyzer = SpeechAnalyzer(modules: [transcriber])

        async let collected: [TimedWord] = {
            var words: [TimedWord] = []
            for try await result in transcriber.results {
                words += timedWords(in: result.text)
            }
            return words
        }()

        // `finishAfterFile` ends the results stream once the file is through; with `analyzeSequence` +
        // `finalizeAndFinish` the stream stays open and the collector never returns.
        try await analyzer.start(inputAudioFile: audioFile, finishAfterFile: true)
        return try await collected
    }

    /// Each run of the transcript carries the time range it was heard in.
    private static func timedWords(in text: AttributedString) -> [TimedWord] {
        var words: [TimedWord] = []
        for run in text.runs {
            guard let range = run.audioTimeRange else { continue }
            let pieces = String(text[run.range].characters).split(whereSeparator: \.isWhitespace)
            for piece in pieces {
                words.append(TimedWord(text: String(piece), start: range.start.seconds, end: range.end.seconds))
            }
        }
        return words
    }

    // MARK: - SFSpeechRecognizer fallback

    private static func legacyWords(in file: URL, locale: Locale) async throws -> [TimedWord] {
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard status == .authorized else { throw Failure.notAuthorized }
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw Failure.unavailable(locale)
        }

        let request = SFSpeechURLRecognitionRequest(url: file)
        request.shouldReportPartialResults = false
        request.taskHint = .dictation

        // The recognition task keeps streaming audio to the server until it is told to stop. A deleted take
        // or a closed editor cancels the Swift task; the handler passes that on so the request ends too.
        let holder = TaskHolder()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let once = ResumeOnce(continuation)
                let task = recognizer.recognitionTask(with: request) { result, error in
                    if let error {
                        once.resume(.failure(error))
                    } else if let result, result.isFinal {
                        // Converted inside the callback: SFTranscription itself isn't Sendable.
                        let words = result.bestTranscription.segments.map {
                            TimedWord(text: $0.substring, start: $0.timestamp, end: $0.timestamp + $0.duration)
                        }
                        once.resume(.success(words))
                    }
                }
                holder.set(task)
            }
        } onCancel: {
            holder.cancel()
        }
    }

    /// Hands the recognition task to the cancellation handler; `cancel` may arrive before or after `set`.
    private final class TaskHolder: @unchecked Sendable {
        private let lock = NSLock()
        private var task: SFSpeechRecognitionTask?
        private var cancelled = false

        func set(_ task: SFSpeechRecognitionTask) {
            lock.withLock {
                self.task = task
                if cancelled { task.cancel() }
            }
        }

        func cancel() {
            lock.withLock {
                cancelled = true
                task?.cancel()
            }
        }
    }

    /// The recognition callback can fire after the final result; only the first outcome counts.
    private final class ResumeOnce: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<[TimedWord], any Error>?

        init(_ continuation: CheckedContinuation<[TimedWord], any Error>) {
            self.continuation = continuation
        }

        func resume(_ result: Result<[TimedWord], any Error>) {
            lock.withLock {
                continuation?.resume(with: result)
                continuation = nil
            }
        }
    }
}
