import AVFoundation

/// Peak levels of an audio file, one per `bucket` seconds, normalised to 0...1.
nonisolated struct Waveform: Sendable {
    static let bucket = 0.02

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
                        peaks.append(Float(current) / Float(Int16.max))
                        current = 0
                        filled = 0
                    }
                }
            }
        }
        if filled > 0 { peaks.append(Float(current) / Float(Int16.max)) }

        // Normalise so a quiet recording still shows shape; silence stays flat.
        let top = peaks.max() ?? 0
        guard top > 0.01 else { return Waveform(peaks: peaks) }
        return Waveform(peaks: peaks.map { min($0 / top, 1) })
    }
}
