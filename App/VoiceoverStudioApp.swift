import SwiftUI

@main
struct VoiceoverStudioApp: App {
    @State private var app: AppModel
    @State private var editor: EditorModel

    init() {
        let app = AppModel()
        _app = State(initialValue: app)
        _editor = State(initialValue: EditorModel(client: app.client))
    }

    var body: some Scene {
        WindowGroup {
            EditorView(model: editor)
                .environment(app)
        }
    }
}
