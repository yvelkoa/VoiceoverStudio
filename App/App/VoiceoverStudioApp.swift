import SwiftUI

@main
struct VoiceoverStudioApp: App {
    @State private var app = AppModel()

    init() {
        // Process-wide state belongs to the app's start, not to a model that tests and previews also build.
        AudioSession.configurePlayback()
    }

    var body: some Scene {
        WindowGroup {
            ProjectListView()
                .environment(app)
        }
    }
}
