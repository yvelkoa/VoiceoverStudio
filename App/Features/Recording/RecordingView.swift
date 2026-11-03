import AVFoundation
import SwiftUI
import VoiceoverKit

/// Full-screen recording: the video on top, a frame strip to scrub, lanes of takes, and the record button.
struct RecordingView: View {
    @Bindable var model: EditorModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale

    @State private var strip: CGImage?
    /// Seeks are coalesced: at most one in flight, the latest requested time waits for it.
    @State private var isSeeking = false
    @State private var pendingSeek: Double?
    @State private var currentTime: Double = 0
    @State private var isScrubbing = false
    @State private var isPlaying = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                video
                characterChips
                TimelineStrip(
                    player: model.player,
                    strip: strip,
                    duration: model.videoDuration,
                    segments: model.project.segments,
                    waveforms: model.project.waveforms,
                    liveRecording: model.liveRecording,
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
        .task(id: model.videoURL) { await loadStrip() }
        .task(id: model.player.map(ObjectIdentifier.init)) { await followPlayer() }
        .onChange(of: model.isRecording) { _, recording in
            // Recording starts and stops the player itself; keep the transport in step.
            isPlaying = recording || (model.player?.rate ?? 0) > 0
            if !recording, let player = model.player { currentTime = player.currentTime().seconds }
        }
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
        HStack(spacing: 28) {
            Button {
                togglePlayback()
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .frame(width: 36, height: 36)
            }
            .disabled(model.isRecording || model.player == nil)

            Button {
                if model.isRecording { model.stopRecording() } else { model.startRecording() }
            } label: {
                ZStack {
                    Circle().stroke(.red, lineWidth: 3).frame(width: 52, height: 52)
                    if model.isRecording {
                        RoundedRectangle(cornerRadius: 4).fill(.red).frame(width: 20, height: 20)
                    } else {
                        Circle().fill(.red).frame(width: 42, height: 42)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(!model.isRecording && !model.canRecord)
            .accessibilityLabel(model.isRecording ? "Stop recording" : "Record")

            Button {
                if let last = model.project.takes.max(by: { $0.sequence < $1.sequence }) {
                    model.delete(last)
                    scrub(to: last.start)
                }
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.title3)
                    .frame(width: 36, height: 36)
            }
            .disabled(model.isRecording || model.project.takes.isEmpty)
            .accessibilityLabel("Delete last take")
        }
    }

    // MARK: - Behaviour

    private func loadStrip() async {
        guard let url = model.videoURL, model.videoDuration > 0 else { return }
        strip = try? await FrameStrip.image(
            for: url,
            duration: model.videoDuration,
            interval: 1,
            cellSize: CGSize(width: TimelineStrip.pointsPerSecond, height: TimelineStrip.frameHeight),
            scale: displayScale
        )
    }

    private func followPlayer() async {
        guard let player = model.player else { return }
        currentTime = player.currentTime().seconds
        for await time in player.timeUpdates(every: 0.1) {
            currentTime = time
            isPlaying = player.rate > 0
        }
    }

    /// Drag events arrive faster than a 60 fps video can seek; only the newest pending time is honoured.
    private func scrub(to time: Double) {
        guard let player = model.player else { return }
        player.pause()
        isPlaying = false
        currentTime = time
        pendingSeek = time
        guard !isSeeking else { return }
        seekNext()
    }

    private func seekNext() {
        guard let player = model.player, let time = pendingSeek else { return }
        pendingSeek = nil
        isSeeking = true
        let tolerance = CMTime(value: 1, timescale: 30)
        let target = CMTime(seconds: time, preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: tolerance, toleranceAfter: tolerance) { _ in
            Task { @MainActor in
                isSeeking = false
                seekNext()
            }
        }
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
