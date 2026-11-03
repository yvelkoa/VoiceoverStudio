import SwiftUI
import VoiceoverKit

/// Photos-style scrubber: a strip of frames scrolls under a fixed playhead; takes are drawn in lanes below.
///
/// Scrolling the strip moves the playhead (and seeks the player); while the video plays the strip follows
/// the player. `isScrubbing` tells the owner which direction the sync currently goes.
struct TimelineStrip: View {
    let frames: [FrameStrip.Frame]
    let duration: Double
    let segments: [AudioSegment]
    let characters: [Character]
    let currentTime: Double
    let isPlaying: Bool
    let isLocked: Bool
    @Binding var isScrubbing: Bool
    let onScrub: (Double) -> Void

    static let pointsPerSecond: CGFloat = 56
    static let frameHeight: CGFloat = 64
    private static let laneHeight: CGFloat = 8
    private static let laneSpacing: CGFloat = 3

    @State private var position = ScrollPosition(x: 0)
    /// Last offset reported by the scroll view, to detect drift between the follow animation and the player.
    @State private var observedOffset: CGFloat = 0
    /// Follow animations drift after seeks or stalls; past this the strip re-anchors to the player.
    private static let driftTolerance = 0.12

    private var pointsPerSecond: CGFloat { Self.pointsPerSecond }
    private var contentWidth: CGFloat { CGFloat(duration) * pointsPerSecond }
    private var lanesHeight: CGFloat {
        CGFloat(max(characters.count, 1)) * (Self.laneHeight + Self.laneSpacing)
    }

    var body: some View {
        GeometryReader { geometry in
            let halfWidth = geometry.size.width / 2
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 6) {
                    frameRow
                    lanes
                }
                .padding(.horizontal, halfWidth)
            }
            .scrollPosition($position)
            .scrollDisabled(isLocked)
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.x } action: { _, offset in
                observedOffset = offset
                guard isScrubbing else { return }
                onScrub(min(max(Double(offset / pointsPerSecond), 0), duration))
            }
            .onScrollPhaseChange { _, phase in
                isScrubbing = phase != .idle && phase != .animating
            }
            .onChange(of: isPlaying) { _, playing in
                guard !isScrubbing else { return }
                if playing { startFollowing(from: currentTime) } else { jump(to: currentTime) }
            }
            .onChange(of: currentTime) { _, time in
                guard !isScrubbing else { return }
                if isPlaying {
                    // One long linear animation keeps the strip moving at display rate; only re-anchor on drift.
                    let shown = Double(observedOffset / pointsPerSecond)
                    if abs(shown - time) > Self.driftTolerance { startFollowing(from: time) }
                } else {
                    jump(to: time)
                }
            }
            .overlay {
                playhead
            }
        }
        .frame(height: Self.frameHeight + 6 + lanesHeight)
    }

    /// Scrolls at exactly playback speed from `time` to the end of the video.
    private func startFollowing(from time: Double) {
        jump(to: time)
        let remaining = max(duration - time, 0)
        guard remaining > 0 else { return }
        withAnimation(.linear(duration: remaining)) {
            position.scrollTo(x: contentWidth)
        }
    }

    /// Moves the strip without animation, cancelling any follow animation in flight.
    private func jump(to time: Double) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            position.scrollTo(x: CGFloat(time) * pointsPerSecond)
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
                    Capsule().fill(.quaternary).frame(width: contentWidth, height: Self.laneHeight)
                    ForEach(segments.filter { $0.characterID == character.id }, id: \.start) { segment in
                        Capsule()
                            .fill(CharacterPalette.color(character.colorIndex))
                            .frame(width: max(CGFloat(segment.duration) * pointsPerSecond, 3), height: Self.laneHeight)
                            .offset(x: CGFloat(segment.start) * pointsPerSecond)
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
