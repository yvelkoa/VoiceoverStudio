import SwiftUI

@main
struct VoiceoverStudioApp: App {
    @State private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            ProjectListView()
                .environment(app)
        }
    }
}
