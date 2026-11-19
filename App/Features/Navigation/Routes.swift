import Foundation
import VoiceoverKit

/// What the root stack pushes. Routes are plain values, so the stack's path is data: it can be built in
/// code (a new project opens itself, the debug hook opens one on launch) and every pushed screen is on it.
///
/// Two types rather than one: the root knows how to show a project, only the open editor knows how to show
/// its voice picker (it needs the editor's model), and each registers the destination for its own type.
enum AppRoute: Hashable {
    case project(UUID)
}

/// Screens pushed from inside an open project.
enum EditorRoute: Hashable {
    /// The voice picker, writing back to the Type-mode voice or to one character.
    case voice(VoiceTarget)
}

enum VoiceTarget: Hashable {
    case script
    case character(Character.ID)
}
