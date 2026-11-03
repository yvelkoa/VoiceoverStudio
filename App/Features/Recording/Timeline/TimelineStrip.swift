import AVFoundation
import SwiftUI
import VoiceoverKit

/// Photos-style scrubber: a strip of frames slides under a fixed playhead; takes are drawn in lanes below.
///
/// While the video plays, `TimelineView` repositions the strip every display frame from the player's clock.
/// Dragging scrubs 1:1 (no inertia, like the Photos video scrubber); a tap seeks to the tapped moment.
struct TimelineStrip: View {
    let player: AVPlayer?
    let strip: CGImage?
    let duration: Double
    let segments: [AudioSegment]
    let waveforms: [Take.ID: Waveform]
    /// A take in progress, drawn in full colour and growing as the level comes in.
    let liveRecording: LiveRecording?
    let characters: [Character]
    let effects: [SoundEffect]
    let onDeleteEffect: (SoundEffect) -> Void
    /// Export range; the strip outside it is dimmed.
    let trim: ClosedRange<Double>?
    /// The time to show when the player is not running (after a seek, a stop, or on first appearance).
    let currentTime: Double
    let isPlaying: Bool
    let isLocked: Bool
    @Binding var isScrubbing: Bool
    let onScrub: (Double) -> Void

    static let pointsPerSecond: CGFloat = 56
    static let frameHeight: CGFloat = 84
    static let laneHeight: CGFloat = 28
    private static let laneSpacing: CGFloat = 5

    @State private var dragStartTime: Double?
    @State private var scrubTime: Double = 0
    @State private var momentum: Task<Void, Never>?
    /// Per-millisecond velocity multiplier, the same curve UIScrollView uses for normal deceleration.
    private static let decelerationRate = 0.998

    private var pointsPerSecond: CGFloat { Self.pointsPerSecond }
    private var contentWidth: CGFloat { CGFloat(duration) * pointsPerSecond }
    static let effectColor = Color.yellow

    private var lanesHeight: CGFloat {
        CGFloat(max(characters.count, 1) + 1) * (Self.laneHeight + Self.laneSpacing)
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
                .overlay(alignment: .leading) { trimShade }
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
        .onDisappear { momentum?.cancel() }
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
                    momentum?.cancel()
                    dragStartTime = displayedTime
                    scrubTime = displayedTime
                    isScrubbing = true
                }
                let time = (dragStartTime ?? 0) - Double(value.translation.width / pointsPerSecond)
                scrubTime = min(max(time, 0), duration)
                onScrub(scrubTime)
            }
            .onEnded { value in
                dragStartTime = nil
                // Points per second of finger movement become seconds of timeline per second.
                let velocity = -Double(value.velocity.width / pointsPerSecond)
                coast(velocity: velocity)
            }
    }

    /// Keeps the strip moving after the finger lifts, slowing like a scroll view, until it stops or hits an end.
    private func coast(velocity initial: Double) {
        momentum?.cancel()
        guard abs(initial) > 0.05 else {
            isScrubbing = false
            return
        }
        momentum = Task {
            var velocity = initial
            var time = scrubTime
            let step = 1.0 / 120
            let decay = pow(Self.decelerationRate, step * 1000)
            while !Task.isCancelled, abs(velocity) > 0.02 {
                try? await Task.sleep(for: .seconds(step))
                guard !Task.isCancelled else { return }
                time = min(max(time + velocity * step, 0), duration)
                velocity *= decay
                scrubTime = time
                onScrub(time)
                if time <= 0 || time >= duration { break }
            }
            if !Task.isCancelled { isScrubbing = false }
        }
    }

    @ViewBuilder
    private var trimShade: some View {
        if let trim {
            let head = CGFloat(trim.lowerBound) * pointsPerSecond
            let tail = contentWidth - CGFloat(trim.upperBound) * pointsPerSecond
            HStack(spacing: 0) {
                Rectangle().fill(.black.opacity(0.55)).frame(width: max(head, 0))
                Rectangle().stroke(Color.accentColor, lineWidth: 2)
                    .frame(width: max(contentWidth - head - tail, 0))
                Rectangle().fill(.black.opacity(0.55)).frame(width: max(tail, 0))
            }
            .allowsHitTesting(false)
        }
    }

    private var frameRow: some View {
        Group {
            if let strip {
                Image(decorative: strip, scale: 1)
                    .resizable()
                    .frame(width: contentWidth, height: Self.frameHeight)
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.quaternary)
                    .frame(width: contentWidth, height: Self.frameHeight)
                    .overlay { ProgressView() }
            }
        }
        .clipShape(.rect(cornerRadius: 6))
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
            effectsLane
        }
    }

    /// Generated sounds share one lane; long-press a clip to delete it.
    private var effectsLane: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 4)
                .fill(.quaternary)
                .frame(width: contentWidth, height: Self.laneHeight)
                .overlay(alignment: .leading) {
                    if effects.isEmpty {
                        Label("Effects", systemImage: "sparkles")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 6)
                    }
                }
            ForEach(effects) { effect in
                SegmentView(
                    segment: AudioSegment(
                        takeID: effect.id, characterID: effect.id, start: effect.start, sourceOffset: 0, duration: effect.duration
                    ),
                    waveform: waveforms[effect.id],
                    color: Self.effectColor,
                    pointsPerSecond: pointsPerSecond
                )
                .overlay(alignment: .leading) {
                    Text(effect.prompt)
                        .font(.caption2)
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                        .padding(.leading, 4)
                        .frame(maxWidth: CGFloat(effect.duration) * pointsPerSecond - 4, alignment: .leading)
                }
                .contextMenu {
                    Button("Delete effect", systemImage: "trash", role: .destructive) { onDeleteEffect(effect) }
                }
                .offset(x: CGFloat(effect.start) * pointsPerSecond)
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
