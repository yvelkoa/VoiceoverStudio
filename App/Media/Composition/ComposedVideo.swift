import AVFoundation
import UIKit
import VoiceoverKit

/// Everything needed to both preview (AVPlayer) and export (AVAssetExportSession) the same edit.
nonisolated struct ComposedVideo {
    let composition: AVMutableComposition
    /// Which kind each audio track carries; the mix is rebuilt from this whenever a level changes.
    let trackKinds: [CMPersistentTrackID: AudioKind]
    /// Kept as a value type so export can add the caption layers without copying an object graph.
    let videoConfiguration: AVVideoComposition.Configuration

    var videoComposition: AVVideoComposition { AVVideoComposition(configuration: videoConfiguration) }

    /// A fresh mix at the given levels. Cheap: no media is touched, so it can follow a slider live.
    func audioMix(_ levels: MixLevels) -> AVMutableAudioMix {
        let mix = AVMutableAudioMix()
        mix.inputParameters = composition.tracks(withMediaType: .audio).compactMap { track in
            guard let kind = trackKinds[track.trackID] else { return nil }
            let parameters = AVMutableAudioMixInputParameters(track: track)
            parameters.setVolume(levels.level(for: kind), at: .zero)
            return parameters
        }
        return mix
    }
}
