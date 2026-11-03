import AVFoundation
import SwiftUI
import VoiceoverKit

/// Photos-style scrubber: a strip of frames slides under a fixed playhead; takes are drawn in lanes below.
///
/// While the video plays, `TimelineView` repositions the strip every display frame from the player's clock.
/// Dragging scrubs 1:1 (no inertia, like the Photos video scrubber); a tap seeks to the tapped moment.
struct TimelineStrip: View {
    let player: AVPlayer?
    let frames: [FrameStrip.Frame]
    let duration: Double
    let segments: [AudioSegment]
    let waveforms: [Take.ID: Waveform]
    /// A take in progress, drawn in full colour and growing as the level comes in.
    let liveRecording: LiveRecording?
    let characters: [Character]
    /// The time to show when the player is not running (after a seek, a stop, or on first appearance).
    let currentTime: Double
    let isPlaying: Bool
    let isLocked: Bool
    @Binding var isScrubbing: Bool
    let onScrub: (Double) -> Void

    static let pointsPerSecond: CGFloat = 56
    static let frameHeight: CGFloat = 64
    static let laneHeight: CGFloat = 22
    private static let laneSpacing: CGFloat = 4

    @State private var dragStartTime: Double?
    @State private var scrubTime: Double = 0

    private var pointsPerSecond: CGFloat { Self.pointsPerSecond }
    private var contentWidth: CGFloat { CGFloat(duration) * pointsPerSecond }
    private var lanesHeight: CGFloat {
        CGFloat(max(characters.count, 1)) * (Self.laneHeight + Self.laneSpacing)
    }

    var body: some View {
        GeometryReader { geometry in
            let center = geometry.size.width / 2
            TimelineView(.animation(paused: !isPlaying || isScrubbing)) { _ in
                let time = displayedTime
                VStack(alignment: .leading, spacing: 6) {
                    frameRow
                    lanes
                }
                .offset(x: center - CGFloat(time) * pointsPerSecond)
            }
            .frame(width: geometry.size.width, alignment: .leading)
            .clipped()
            .contentShape(.rect)
            .gesture(scrubGesture, isEnabled: !isLocked)
            .onTapGesture { location in
                guard !isLocked else { return }
                let tapped = displayedTime + Double((location.x - center) / pointsPerSecond)
                onScrub(min(max(tapped, 0), duration))
            }
            .overlay { playhead }
        }
        .frame(height: Self.frameHeight + 6 + lanesHeight)
    }

    /// Player clock while playing, the drag position while scrubbing, otherwise the time the owner last set.
    private var displayedTime: Double {
        if isScrubbing { return scrubTime }
        if isPlaying, let player { return player.currentTime().seconds }
        return currentTime
    }

    private var scrubGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                if dragStartTime == nil {
                    dragStartTime = displayedTime
                    scrubTime = displayedTime
                    isScrubbing = true
                }
                let time = (dragStartTime ?? 0) - Double(value.translation.width / pointsPerSecond)
                scrubTime = min(max(time, 0), duration)
                onScrub(scrubTime)
            }
            .onEnded { _ in
                dragStartTime = nil
                isScrubbing = false
            }
    }

    private var frameRow: some View {
        HStack(spacing: 0) {
            if frames.isEmpty {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.quaternary)
                    .frame(width: contentWidth, height: Self.frameHeight)
                    .overlay { ProgressView() }
            } else {
                ForEach(frames) { frame in
                    Image(decorative: frame.image, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: frameWidth, height: Self.frameHeight)
                        .clipped()
                }
            }
        }
        .frame(width: contentWidth, alignment: .leading)
        .clipShape(.rect(cornerRadius: 6))
    }

    private var frameWidth: CGFloat {
        guard frames.count > 1 else { return contentWidth }
        return contentWidth / CGFloat(frames.count)
    }

    /// One lane per character, in declaration order; segments already have overlaps resolved.
    private var lanes: some View {
        VStack(alignment: .leading, spacing: Self.laneSpacing) {
            ForEach(characters) { character in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.quaternary)
                        .frame(width: contentWidth, height: Self.laneHeight)
                    ForEach(segments.filter { $0.characterID == character.id }, id: \.start) { segment in
                        SegmentView(
                            segment: segment,
                            waveform: waveforms[segment.takeID],
                            color: CharacterPalette.color(character.colorIndex),
                            pointsPerSecond: pointsPerSecond
                        )
                        .offset(x: CGFloat(segment.start) * pointsPerSecond)
                    }
                    if let live = liveRecording, live.characterID == character.id {
                        let elapsed = Double(live.waveform.peaks.count) * Waveform.bucket
                        SegmentView(
                            segment: AudioSegment(
                                takeID: UUID(), characterID: character.id, start: live.start, sourceOffset: 0, duration: elapsed
                            ),
                            waveform: live.waveform,
                            color: CharacterPalette.color(character.colorIndex),
                            pointsPerSecond: pointsPerSecond,
                            isLive: true
                        )
                        .offset(x: CGFloat(live.start) * pointsPerSecond)
                    }
                }
            }
        }
    }

    private var playhead: some View {
        VStack(spacing: 0) {
            Triangle().fill(.primary).frame(width: 10, height: 6)
            Rectangle().fill(.primary).frame(width: 2)
        }
        .allowsHitTesting(false)
    }

    private struct Triangle: Shape {
        func path(in rect: CGRect) -> Path {
            Path { path in
                path.move(to: CGPoint(x: rect.minX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
                path.closeSubpath()
            }
        }
    }
}

/// A take slice on its lane: a tinted block with the recording's waveform, so a silent take is obvious.
private struct SegmentView: View {
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
