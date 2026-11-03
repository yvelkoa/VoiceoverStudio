import AVFoundation
import SwiftUI
import VoiceoverKit

/// A take slice on its lane: a tinted block with the recording's waveform, so a silent take is obvious.
struct SegmentView: View {
    let segment: AudioSegment
    let waveform: Waveform?
    let color: Color
    let pointsPerSecond: CGFloat
    var isLive = false

    var body: some View {
        let width = max(CGFloat(segment.duration) * pointsPerSecond, 3)
        RoundedRectangle(cornerRadius: 4)
            .fill(color.opacity(isLive ? 0.6 : 0.35))
            .frame(width: width, height: TimelineStrip.laneHeight)
            .overlay {
                if let waveform {
                    Canvas { context, size in
                        let count = Int(size.width / 2)
                        let samples = waveform.levels(from: segment.sourceOffset, duration: segment.duration, count: count)
                        for (index, level) in samples.enumerated() {
                            let height = max(1, CGFloat(level) * size.height)
                            let rect = CGRect(x: CGFloat(index) * 2, y: (size.height - height) / 2, width: 1.5, height: height)
                            context.fill(Path(roundedRect: rect, cornerRadius: 0.75), with: .color(isLive ? .white : color))
                        }
                    }
                    .clipShape(.rect(cornerRadius: 4))
                }
            }
    }
}
