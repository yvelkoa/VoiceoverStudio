import AVFoundation
import SwiftUI
import VoiceoverKit

/// Watch the current edit end to end, edge to edge: the picture fills the screen, captions are drawn live,
/// and the few controls float over it and step aside while it plays. A tap brings them back.
struct PreviewScreen: View {
    let player: AVPlayer
    let captions: [Caption]
    let duration: Double
    /// The export range; playback is confined to it so the preview shows exactly what will be exported.
    var range: ClosedRange<Double>?
    @Environment(\.dismiss) private var dismiss

    @State private var currentTime: Double = 0
    @State private var isPlaying = false
    @State private var isScrubbing = false
    @State private var showsControls = true

    /// What can be played and scrubbed: the export range, or the whole video.
    private var bounds: ClosedRange<Double> {
        range ?? 0...max(duration, 0.1)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            PlayerLayerView(player: player)
                .ignoresSafeArea()
            CaptionOverlay(captions: captions, currentTime: currentTime)
            if showsControls {
                controls.transition(.opacity)
            }
        }
        .contentShape(.rect)
        .onTapGesture { showsControls.toggle() }
        .animation(.easeOut(duration: 0.2), value: showsControls)
        .statusBarHidden()
        .persistentSystemOverlays(showsControls ? .automatic : .hidden)
        // Not `preferredColorScheme`: that one recolours the whole window, so the editor underneath would flash
        // dark while this screen grows out of it.
        .environment(\.colorScheme, .dark)
        .task(id: ObjectIdentifier(player)) {
            for await time in player.timeUpdates(every: 0.05) where !isScrubbing {
                currentTime = time
            }
        }
        .task(id: ObjectIdentifier(player)) {
            for await playing in player.playingUpdates() {
                isPlaying = playing
            }
        }

        // The controls leave once the picture has been running for a moment; any change starts the wait over.
        .task(id: [showsControls, isPlaying, isScrubbing]) {
            guard showsControls, isPlaying, !isScrubbing else { return }

            try? await Task.sleep(for: .seconds(2.5))
            if !Task.isCancelled { showsControls = false }
        }
        .onAppear {
            if let range {
                player.currentItem?.forwardPlaybackEndTime = CMTime(seconds: range.upperBound, preferredTimescale: 600)
            }

            seek(to: bounds.lowerBound)
            player.play()
        }
        .onDisappear {
            player.pause()
            player.currentItem?.forwardPlaybackEndTime = .invalid
        }
    }

    // MARK: - Controls

    private var controls: some View {
        VStack {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel("Done")
                Spacer()
            }
            Spacer()
            HStack(spacing: 14) {
                Button { togglePlayback() } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .frame(width: 30, height: 30)
                }
                .accessibilityLabel(isPlaying ? "Pause" : "Play")
                Slider(value: scrubBinding, in: bounds) { editing in
                    isScrubbing = editing
                }

                let length = bounds.upperBound - bounds.lowerBound
                Text(verbatim: "\(timecode(currentTime - bounds.lowerBound)) / \(timecode(length))")
                    .font(.footnote.weight(.medium))
                    .monospacedDigit()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassEffect(.regular, in: .capsule)
        }
        .tint(.white)
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var scrubBinding: Binding<Double> {
        Binding(
            get: { min(max(currentTime, bounds.lowerBound), bounds.upperBound) },
            set: { time in
                currentTime = time
                seek(to: time)
            }
        )
    }

    // MARK: - Behaviour

    private func togglePlayback() {
        if player.rate > 0 {
            player.pause()
        } else {
            // At the end of the range the player stands still; Play starts the range over.
            if currentTime >= bounds.upperBound - 0.05 { seek(to: bounds.lowerBound) }
            player.play()
        }

        isPlaying = player.rate > 0
    }

    private func seek(to time: Double) {
        let tolerance = CMTime(value: 1, timescale: 30)
        player.seek(to: CMTime(seconds: time, preferredTimescale: 600), toleranceBefore: tolerance, toleranceAfter: tolerance)
    }

    private func timecode(_ seconds: Double) -> String {
        Duration.seconds(max(seconds.isFinite ? seconds : 0, 0)).formatted(.time(pattern: .minuteSecond))
    }
}
