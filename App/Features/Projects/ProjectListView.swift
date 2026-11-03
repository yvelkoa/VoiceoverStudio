import SwiftUI

/// Home: every project on this device, newest first. Tap to edit, swipe to delete, long-press to rename.
struct ProjectListView: View {
    @Environment(AppModel.self) private var app

    @State private var path: [UUID] = []
    @State private var showsSettings = false
    @State private var renaming: ProjectSummary?
    @State private var newTitle = ""

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if app.store.summaries.isEmpty {
                    ContentUnavailableView {
                        Label("No projects yet", systemImage: "film.stack")
                    } description: {
                        Text("A project is one video with its takes, voices and effects.")
                    } actions: {
                        Button("New project", systemImage: "plus") { createProject() }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        ForEach(app.store.summaries) { summary in
                            NavigationLink(value: summary.id) { ProjectRow(summary: summary) }
                                .contextMenu {
                                    Button("Rename", systemImage: "pencil") {
                                        newTitle = summary.title
                                        renaming = summary
                                    }
                                    Button("Delete", systemImage: "trash", role: .destructive) { app.store.delete(summary.id) }
                                }
                        }
                        .onDelete { offsets in
                            for index in offsets { app.store.delete(app.store.summaries[index].id) }
                        }
                    }
                }
            }
            .navigationTitle("Voiceover Studio")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Settings", systemImage: "gearshape") { showsSettings = true }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("New project", systemImage: "plus") { createProject() }
                }
            }
            .navigationDestination(for: UUID.self) { id in
                ProjectScreen(projectID: id)
            }
            .sheet(isPresented: $showsSettings) { SettingsView() }
            .alert("Rename project", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Title", text: $newTitle)
                Button("Save") {
                    if let renaming { app.store.rename(renaming.id, to: newTitle) }
                    renaming = nil
                }
                Button("Cancel", role: .cancel) { renaming = nil }
            }
            .onAppear { app.store.refresh() }
            .task { await openDebugProject() }
        }
    }

    private func createProject() {
        let project = app.store.create()
        path.append(project.id)
    }

    /// With `VOICEOVER_DEBUG_VIDEO` set, open a fresh project straight away; the editor loads the video.
    private func openDebugProject() async {
        #if DEBUG
        guard ProcessInfo.processInfo.environment["VOICEOVER_DEBUG_VIDEO"] != nil, path.isEmpty else { return }
        createProject()
        #endif
    }
}
