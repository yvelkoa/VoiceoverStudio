import AVFoundation
import SwiftUI
import VoiceoverKit

/// The top of the editor: the video the project is about, playing the current edit with its captions, and
/// under it the whole edit as lanes.
/// Everything below it (characters, takes, sounds) is about this picture, so it stays in view while they scroll.
///
/// Always dark, like the recorder: a video reads best on black whatever the app's appearance is.
struct EditorStage: View {
    let model: EditorModel
    /// A picked video is being copied in.
    let isLoading: Bool
    /// The keyboard is up: the picture gives most of its height to the field being typed in.
    var isCompact = false
    /// The picture is where the full-screen preview grows from and shrinks back to.
    let previewSource: Namespace.ID
    let onPickVideo: () -> Void
    let onExpand: () -> Void

    /// The picture's share of the stage; the timeline and the controls come on top of it.
    private static let videoHeight: CGFloat = 200
    private static let compactVideoHeight: CGFloat = 96
    private static let emptyHeight: CGFloat = 290
    private static let corner: CGFloat = 24
    static let previewID = "preview"

    @State private var currentTime: Double = 0
    @State private var isPlaying = false
    @State private var showsMix = false

    var body: some View {
        Group {
            if let player = model.player {
                loaded(player)
            } else {
                empty
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }

    // MARK: - With a video

    private func loaded(_ player: AVPlayer) -> some View {
        VStack(spacing: 0) {
            PlayerLayerView(player: player)
                .frame(height: isCompact ? Self.compactVideoHeight : Self.videoHeight)
                .matchedTransitionSource(id: Self.previewID, in: previewSource)
                .overlay { CaptionOverlay(captions: model.captions, currentTime: currentTime, compact: true) }
                .overlay {
                    if isLoading {
                        ProgressView()
                            .controlSize(.large)
                    } else if !isPlaying {
                        Image(systemName: "play.fill")
                            .font(.title)
                            .foregroundStyle(.white)
                            .frame(width: 64, height: 64)
                            .background(.black.opacity(0.35), in: .circle)
                            .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    }
                }
                .contentShape(.rect)
                .onTapGesture { toggle(player) }
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(isPlaying ? "Pause" : "Play")

            if !isCompact {
                timeline(player)
            }
            controls(player)
        }
        .background(.black)
        .clipShape(.rect(cornerRadius: Self.corner))
        .environment(\.colorScheme, .dark)
        .animation(.easeOut(duration: 0.15), value: isPlaying)
        .task(id: ObjectIdentifier(player)) {
            currentTime = player.currentTime().seconds
            for await time in player.timeUpdates(every: 0.1) {
                currentTime = time
            }
        }
        .task(id: ObjectIdentifier(player)) {
            for await playing in player.playingUpdates() {
                isPlaying = playing
            }
        }
    }

    /// The edit's overview: who speaks when, the effects, the music. Dragging it moves the playhead.
    private func timeline(_ player: AVPlayer) -> some View {
        EditorTimeline(
            project: model.project,
            trim: model.exportRange,
            currentTime: currentTime,
            player: player,
            isPlaying: isPlaying
        ) { time in
            currentTime = time
            let tolerance = CMTime(value: 1, timescale: 30)
            player.seek(to: CMTime(seconds: time, preferredTimescale: 600), toleranceBefore: tolerance, toleranceAfter: tolerance)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    private func controls(_ player: AVPlayer) -> some View {
        HStack(spacing: 2) {
            stageButton(isPlaying ? "Pause" : "Play", systemImage: isPlaying ? "pause.fill" : "play.fill") { toggle(player) }
            Text(verbatim: "\(timecode(currentTime)) / \(timecode(model.videoDuration))")
                .font(.footnote.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.75))
            Spacer()
            stageButton("Mix", systemImage: "slider.horizontal.3") { showsMix = true }
                .popover(isPresented: $showsMix) {
                    MixPopover(project: model.project) { model.applyMix() }
                }
            stageButton("Replace video", systemImage: "film", action: onPickVideo)
                .disabled(model.isBusy || isLoading)
            stageButton("Preview", systemImage: "arrow.up.left.and.arrow.down.right", action: onExpand)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .tint(.white)
    }

    private func stageButton(_ label: LocalizedStringKey, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.medium))
                .frame(width: 44, height: 40)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .accessibilityLabel(label)
    }

    private func toggle(_ player: AVPlayer) {
        if player.rate > 0 {
            player.pause()
        } else {
            if currentTime >= model.videoDuration - 0.05 { player.seek(to: .zero) }
            player.play()
        }

        isPlaying = player.rate > 0
    }

    private func timecode(_ seconds: Double) -> String {
        Duration.seconds(seconds.isFinite ? seconds : 0).formatted(.time(pattern: .minuteSecond))
    }

    // MARK: - Without one

    private var empty: some View {
        Button(action: onPickVideo) {
            VStack(spacing: 10) {
                if isLoading {
                    ProgressView()
                        .controlSize(.large)
                } else {
                    WaveformMark()
                        .frame(width: 96, height: 44)
                        .foregroundStyle(.tint)
                }
                Text("Choose a video")
                    .font(.title3.weight(.semibold))
                    .padding(.top, 6)
                Text("A project is one video with its takes, voices and effects.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.tint.opacity(0.08), in: .rect(cornerRadius: Self.corner))
            .overlay {
                RoundedRectangle(cornerRadius: Self.corner)
                    .strokeBorder(.tint.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [7, 6]))
            }
            .contentShape(.rect(cornerRadius: Self.corner))
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .frame(height: Self.emptyHeight)
    }
}

/// The app icon's waveform, drawn: the one mark the empty screens share.
struct WaveformMark: View {
    private static let bars: [CGFloat] = [0.3, 0.55, 0.85, 0.5, 1, 0.65, 0.9, 0.45, 0.7, 0.3]

    var body: some View {
        GeometryReader { geometry in
            let spacing = geometry.size.width / CGFloat(Self.bars.count)
            HStack(alignment: .center, spacing: spacing * 0.45) {
                ForEach(Self.bars.indices, id: \.self) { index in
                    Capsule()
                        .frame(width: spacing * 0.55, height: geometry.size.height * Self.bars[index])
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityHidden(true)
    }
}
