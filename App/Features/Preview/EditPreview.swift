import SwiftUI

/// The edit's full-screen preview, as both the editor and the recorder present it: the model's player and
/// captions, confined to the export range.
struct EditPreview: View {
    let model: EditorModel

    var body: some View {
        if let player = model.player {
            PreviewScreen(player: player, captions: model.captions, range: model.exportRange)
        }
    }
}
