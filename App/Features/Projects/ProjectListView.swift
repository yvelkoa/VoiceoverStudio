import SwiftUI

/// Home: every project on this device as a grid of posters, newest first. Tap to edit, long-press to rename
/// or delete.
struct ProjectListView: View {
    @Environment(AppModel.self) private var app

    /// Holds `AppRoute`s pushed here and `EditorRoute`s pushed from inside an open project.
    @State private var path = NavigationPath()
    @State private var showsSettings = false
    @State private var renaming: ProjectSummary?
    @State private var newTitle = ""

    private static let columns = [GridItem(.adaptive(minimum: 150, maximum: 240), spacing: 16, alignment: .top)]

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
                    ScrollView {
                        LazyVGrid(columns: Self.columns, spacing: 20) {
                            ForEach(app.store.summaries) { summary in
                                NavigationLink(value: AppRoute.project(summary.id)) {
                                    ProjectCard(summary: summary)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button("Rename", systemImage: "pencil") {
                                        newTitle = summary.title
                                        renaming = summary
                                    }
                                    Button("Delete", systemImage: "trash", role: .destructive) {
                                        app.store.delete(summary.id)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .animation(.default, value: app.store.summaries)
                    }
                    .background(Color(.systemGroupedBackground))
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
            .navigationDestination(for: AppRoute.self) { route in
                switch route {
                case .project(let id):
                    ProjectScreen(projectID: id)
                }
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
        path.append(AppRoute.project(project.id))
    }

    /// With `VOICEOVER_DEBUG_VIDEO` set, open a fresh project straight away; the editor loads the video.
    private func openDebugProject() async {
        #if DEBUG
        guard ProcessInfo.processInfo.environment["VOICEOVER_DEBUG_VIDEO"] != nil, path.isEmpty else { return }

        createProject()
        #endif
    }
}

#Preview("Projects") {
    ProjectListView()
        .environment(AppModel.preview(projects: ["Trailer", "Cooking show"]))
}

#Preview("Empty") {
    ProjectListView()
        .environment(AppModel.preview())
}
