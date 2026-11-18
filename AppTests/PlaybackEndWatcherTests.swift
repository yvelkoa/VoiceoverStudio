import AVFoundation
import Testing
@testable import VoiceoverStudio

/// Recording stops itself at the end of the video; the watcher is what notices the end.
struct PlaybackEndWatcherTests {
    private let video = URL(fileURLWithPath: "/nonexistent/video.mov")

    @Test func firesWhenThePlayersItemEnds() async {
        let player = AVPlayer(playerItem: AVPlayerItem(url: video))
        var ended = 0
        let watcher = PlaybackEndWatcher(player: player) { ended += 1 }

        NotificationCenter.default.post(name: AVPlayerItem.didPlayToEndTimeNotification, object: player.currentItem)

        #expect(await eventually { ended == 1 })
        withExtendedLifetime(watcher) {}
    }

    @Test func ignoresAnItemThePlayerNoLongerPlays() async {
        let old = AVPlayerItem(url: video)
        let player = AVPlayer(playerItem: old)
        var ended = 0
        let watcher = PlaybackEndWatcher(player: player) { ended += 1 }
        // A recompose swapped the item mid-take.
        player.replaceCurrentItem(with: AVPlayerItem(url: video))

        NotificationCenter.default.post(name: AVPlayerItem.didPlayToEndTimeNotification, object: old)
        NotificationCenter.default.post(name: AVPlayerItem.didPlayToEndTimeNotification, object: player.currentItem)

        #expect(await eventually { ended == 1 })
        try? await Task.sleep(for: .milliseconds(100))
        #expect(ended == 1)
        withExtendedLifetime(watcher) {}
    }

    @Test func stopsWatchingOnceReleased() async {
        let player = AVPlayer(playerItem: AVPlayerItem(url: video))
        var ended = 0
        var watcher: PlaybackEndWatcher? = PlaybackEndWatcher(player: player) { ended += 1 }
        watcher = nil

        NotificationCenter.default.post(name: AVPlayerItem.didPlayToEndTimeNotification, object: player.currentItem)

        try? await Task.sleep(for: .milliseconds(100))
        #expect(ended == 0)
        _ = watcher
    }
}
