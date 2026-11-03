import AVFoundation
import SwiftUI
import VoiceoverKit

/// Full-screen recording: the video on top, a frame strip to scrub, lanes of takes, and the record button.
struct RecordingView: View {
    @Bindable var model: EditorModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale

    @State private var frames: [FrameStrip.Frame] = []
    @State private var currentTime: Double = 0
    @State private var isScrubbing = false
    @State private var isPlaying = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                video
                characterChips
                TimelineStrip(
                    frames: frames,
                    duration: model.videoDuration,
                    segments: model.project.segments,
                    characters: model.project.characters,
                    currentTime: currentTime,
                    isPlaying: isPlaying,
                    isLocked: model.isRecording,
                    isScrubbing: $isScrubbing,
                    onScrub: scrub
                )
                .padding(.horizontal, -16)
                transport
            }
            .padding(16)
            .background(Color(.systemBackground))
            .navigationTitle(timecode(currentTime))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.disabled(model.isRecording)
                }
            }
        }
        .interactiveDismissDisabled(model.isRecording)
        .task(id: model.videoURL) { await loadFrames() }
        .task(id: model.player.map(ObjectIdentifier.init)) { await followPlayer() }
        .onDisappear { model.player?.pause() }
    }

    // MARK: - Pieces

    @ViewBuilder
    private var video: some View {
        if let player = model.player {
            PlayerLayerView(player: player)
                .background(.black)
                .clipShape(.rect(cornerRadius: 16))
                .overlay { CaptionOverlay(captions: model.captions, currentTime: currentTime) }
                .overlay(alignment: .topLeading) {
                    if model.isRecording {
                        Label("REC", systemImage: "record.circle.fill")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .padding(6)
                            .background(.red, in: .capsule)
                            .padding(10)
                    }
                }
                .frame(maxHeight: .infinity)
        } else {
            ContentUnavailableView("No video", systemImage: "film")
        }
    }

    private var characterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(model.project.characters) { character in
                    let active = model.project.activeCharacterID == character.id
                    Button {
                        model.project.activeCharacterID = character.id
                    } label: {
                        HStack(spacing: 6) {
                            Circle().fill(CharacterPalette.color(character.colorIndex)).frame(width: 8, height: 8)
                            Text(character.name.isEmpty ? "Character" : character.name)
                        }
                        .font(.subheadline.weight(active ? .semibold : .regular))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(active ? AnyShapeStyle(.tint.opacity(0.15)) : AnyShapeStyle(.quaternary), in: .capsule)
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isRecording)
                }
            }
        }
    }

    private var transport: some View {
        HStack(spacing: 24) {
            Button {
                togglePlayback()
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.title2)
                    .frame(width: 44, height: 44)
            }
            .disabled(model.isRecording || model.player == nil)

            Button {
                if model.isRecording { model.stopRecording() } else { model.startRecording() }
            } label: {
                ZStack {
                    Circle().stroke(.red, lineWidth: 4).frame(width: 72, height: 72)
                    if model.isRecording {
                        RoundedRectangle(cornerRadius: 6).fill(.red).frame(width: 30, height: 30)
                    } else {
                        Circle().fill(.red).frame(width: 60, height: 60)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(!model.isRecording && !model.canRecord)
            .accessibilityLabel(model.isRecording ? "Stop recording" : "Record")

            Button {
                if let last = model.project.takes.max(by: { $0.sequence < $1.sequence }) { model.delete(last) }
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.title2)
                    .frame(width: 44, height: 44)
            }
            .disabled(model.isRecording || model.project.takes.isEmpty)
            .accessibilityLabel("Delete last take")
        }
        .padding(.top, 4)
    }

    // MARK: - Behaviour

    private func loadFrames() async {
        guard let url = model.videoURL, model.videoDuration > 0 else { return }
        frames = (try? await FrameStrip.frames(
            for: url,
            duration: model.videoDuration,
            interval: 1,
            height: TimelineStrip.frameHeight,
            scale: displayScale
        )) ?? []
    }

    private func followPlayer() async {
        guard let player = model.player else { return }
        currentTime = player.currentTime().seconds
        for await time in player.timeUpdates(every: 0.1) {
            currentTime = time
            isPlaying = player.rate > 0
        }
    }

    private func scrub(to time: Double) {
        guard let player = model.player else { return }
        player.pause()
        currentTime = time
        player.seek(to: CMTime(seconds: time, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func togglePlayback() {
        guard let player = model.player else { return }
        if player.rate > 0 {
            player.pause()
        } else {
            if currentTime >= model.videoDuration - 0.05 { scrub(to: 0) }
            player.play()
        }
        isPlaying = player.rate > 0
    }

    private func timecode(_ seconds: Double) -> String {
        Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond(padMinuteToLength: 1, fractionalSecondsLength: 1)))
    }
}
