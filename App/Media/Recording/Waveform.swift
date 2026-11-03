import AVFoundation

/// Peak levels of an audio file, one per `bucket` seconds, as linear amplitude 0...1 with a fixed gain.
/// The live meter and the stored waveform use the same scale, so a take looks the same during and after recording.
nonisolated struct Waveform: Sendable {
    static let bucket = 0.02
    /// Speech peaks rarely reach full scale; a little gain makes ordinary takes fill the lane.
    static let gain: Float = 1.6

    /// Linear amplitude from a dBFS meter reading, on the same scale as `load`.
    static func level(fromDecibels decibels: Float) -> Float {
        min(1, powf(10, decibels / 20) * gain)
    }

    let peaks: [Float]

    /// Levels for a slice of the file, resampled to `count` values for drawing.
    func levels(from offset: Double, duration: Double, count: Int) -> [Float] {
        guard !peaks.isEmpty, count.signum() == 1 else { return [] }
        let first = offset / Self.bucket
        let span = duration / Self.bucket
        return (0..<count).map { index in
            let position = first + span * Double(index) / Double(count)
            let bucketIndex = Int(position)
            return bucketIndex < peaks.count ? peaks[bucketIndex] : 0
        }
    }

    /// Reads the whole file as mono 16-bit PCM and keeps the peak of every bucket.
    @concurrent
    static func load(_ url: URL) async throws -> Waveform {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { return Waveform(peaks: []) }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey: 16_000,
        ])
        reader.add(output)
        reader.startReading()

        let samplesPerBucket = Int(16_000 * bucket)
        var peaks: [Float] = []
        var current: Int16 = 0
        var filled = 0

        while let buffer = output.copyNextSampleBuffer(), let block = CMSampleBufferGetDataBuffer(buffer) {
            try Task.checkCancellation()
            var length = 0
            var pointer: UnsafeMutablePointer<CChar>?
            CMBlockBufferGetDataPointer(
                block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &pointer
            )
            guard let pointer else { continue }
            pointer.withMemoryRebound(to: Int16.self, capacity: length / 2) { samples in
                for index in 0..<(length / 2) {
                    current = max(current, Swift.abs(max(samples[index], -Int16.max)))
                    filled += 1
                    if filled == samplesPerBucket {
                        peaks.append(min(1, Float(current) / Float(Int16.max) * gain))
                        current = 0
                        filled = 0
                    }
                }
            }
        }
        if filled > 0 { peaks.append(min(1, Float(current) / Float(Int16.max) * gain)) }
        // copyNextSampleBuffer returns nil both at the end and on failure; a truncated waveform would look like silence.
        if reader.status == .failed, let error = reader.error { throw error }
        return Waveform(peaks: peaks)
    }
}
