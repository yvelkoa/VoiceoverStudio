import AVFoundation

/// Calls `onEnd` when the player's current item plays to its end.
///
/// The item is compared when the notification arrives rather than fixed at the start, so a recompose that
/// swapped the item in the meantime still counts, and an old item finishing elsewhere does not.
final class PlaybackEndWatcher {
    private weak var player: AVPlayer?
    private let onEnd: () -> Void
    private var observer: (any NSObjectProtocol)?

    init(player: AVPlayer, onEnd: @escaping () -> Void) {
        self.player = player
        self.onEnd = onEnd
        observer = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: nil, queue: nil
        ) { [weak self] note in
            let item = (note.object as AnyObject?).map(ObjectIdentifier.init)
            Task { @MainActor in self?.itemEnded(item) }
        }
    }

    isolated deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    private func itemEnded(_ item: ObjectIdentifier?) {
        guard let item, let current = player?.currentItem, ObjectIdentifier(current) == item else { return }

        onEnd()
    }
}
