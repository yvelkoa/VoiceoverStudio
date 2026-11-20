import AVFoundation
import SwiftUI
import VoiceoverKit

/// The whole edit at a glance, fitted to the width: a lane per character, one for effects, one for music,
/// the export range and the playhead. Tap or drag anywhere to move the playhead.
///
/// The recorder's `TimelineStrip` is the tool for working on a moment; this one answers "what is where".
struct EditorTimeline: View {
    let project: Project
    /// Export range; the lanes outside it are dimmed.
    let trim: ClosedRange<Double>?
    let currentTime: Double
    /// While it plays, the playhead follows the player's own clock every display frame; `currentTime` only
    /// arrives ten times a second, which reads as stutter on a line this thin.
    let player: AVPlayer
    let isPlaying: Bool
    let onSeek: (Double) -> Void

    private static let gutter: CGFloat = 18
    private static let spacing: CGFloat = 4

    /// Lanes get thinner when there are many, so the stage keeps its size.
    private var laneHeight: CGFloat {
        rows > 4 ? 10 : 14
    }

    private var rows: Int {
        project.characters.count + 1 + (project.music == nil ? 0 : 1)
    }

    var height: CGFloat {
        CGFloat(rows) * laneHeight + CGFloat(rows - 1) * Self.spacing
    }

    private var duration: Double {
        max(project.videoDuration, 0.01)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            icons

            GeometryReader { geometry in
                let scale = geometry.size.width / CGFloat(duration)

                lanes(scale: scale)
                    .overlay(alignment: .leading) { trimShade(scale: scale, width: geometry.size.width) }
                    .overlay(alignment: .leading) { playhead(scale: scale) }
                    .contentShape(.rect)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                onSeek(min(max(Double(value.location.x / scale), 0), duration))
                            }
                    )
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel("Timeline")
    }

    // MARK: - Pieces

    /// What each lane holds: the character's colour, then effects, then music.
    private var icons: some View {
        VStack(spacing: Self.spacing) {
            ForEach(project.characters) { character in
                Circle()
                    .fill(CharacterPalette.color(character.colorIndex))
                    .frame(width: 7, height: 7)
                    .frame(width: Self.gutter, height: laneHeight)
            }
            laneIcon("sparkles", color: TimelineStrip.effectColor)
            if project.music != nil {
                laneIcon("music.note", color: TimelineStrip.musicColor)
            }
        }
    }

    private func laneIcon(_ systemImage: String, color: Color) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: Self.gutter, height: laneHeight)
    }

    private func lanes(scale: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: Self.spacing) {
            ForEach(project.characters) { character in
                lane {
                    ForEach(project.segments.filter { $0.characterID == character.id }, id: \.self) { segment in
                        clip(segment, color: CharacterPalette.color(character.colorIndex), scale: scale)
                    }
                }
            }

            lane {
                ForEach(project.effects) { effect in
                    clip(
                        AudioSegment(
                            takeID: effect.id,
                            characterID: effect.id,
                            start: effect.start,
                            sourceOffset: 0,
                            duration: effect.duration
                        ),
                        color: TimelineStrip.effectColor,
                        scale: scale
                    )
                }
            }

            if let music = project.music {
                lane {
                    let start = project.musicStart
                    clip(
                        AudioSegment(
                            takeID: music.id,
                            characterID: music.id,
                            start: start,
                            sourceOffset: 0,
                            duration: min(music.duration, duration - start)
                        ),
                        color: TimelineStrip.musicColor,
                        scale: scale
                    )
                }
            }
        }
    }

    private func lane(@ViewBuilder clips: () -> some View) -> some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3)
                .fill(.white.opacity(0.12))
                .frame(height: laneHeight)
            clips()
        }
    }

    private func clip(_ segment: AudioSegment, color: Color, scale: CGFloat) -> some View {
        SegmentView(
            segment: segment,
            waveform: project.waveforms[segment.takeID],
            color: color,
            pointsPerSecond: scale,
            height: laneHeight
        )
        .offset(x: CGFloat(segment.start) * scale)
    }

    @ViewBuilder
    private func trimShade(scale: CGFloat, width: CGFloat) -> some View {
        if let trim {
            let head = CGFloat(trim.lowerBound) * scale
            let tail = width - CGFloat(trim.upperBound) * scale

            HStack(spacing: 0) {
                Rectangle()
                    .fill(.black.opacity(0.6))
                    .frame(width: max(head, 0))
                Spacer(minLength: 0)
                Rectangle()
                    .fill(.black.opacity(0.6))
                    .frame(width: max(tail, 0))
            }
            .allowsHitTesting(false)
        }
    }

    private func playhead(scale: CGFloat) -> some View {
        TimelineView(.animation(paused: !isPlaying)) { _ in
            let time = isPlaying ? player.currentTime().seconds : currentTime

            Capsule()
                .fill(.white)
                .frame(width: 2)
                .padding(.vertical, -3)
                .offset(x: CGFloat(min(max(time.isFinite ? time : 0, 0), duration)) * scale - 1)
        }
        .allowsHitTesting(false)
    }
}
