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

private struct ProjectRow: View {
    let summary: ProjectSummary
    @State private var image: UIImage?

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let image {
                    Image(uiImage: image).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "film").font(.title2).foregroundStyle(.secondary)
                }
            }
            .task(id: summary.thumbnail) {
                // Decoded off the main thread so a long list scrolls without hitches.
                guard let path = summary.thumbnail?.path else { return }
                image = await Task.detached(priority: .utility) { UIImage(contentsOfFile: path) }.value
            }
            .frame(width: 54, height: 72)
            .background(.quaternary)
            .clipShape(.rect(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(summary.title).font(.headline)
                Text(details).font(.subheadline).foregroundStyle(.secondary)
                Text(summary.updatedAt, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    private var details: String {
        guard summary.hasVideo else { return "No video yet" }
        var parts = [Duration.seconds(summary.videoDuration).formatted(.time(pattern: .minuteSecond))]
        parts.append("\(summary.takeCount) \(summary.takeCount == 1 ? "take" : "takes")")
        if summary.isExported { parts.append("exported") }
        return parts.joined(separator: " · ")
    }
}

/// Loads a project from disk and hosts its editor for as long as it is on screen.
struct ProjectScreen: View {
    let projectID: UUID
    @Environment(AppModel.self) private var app
    @State private var model: EditorModel?
    @State private var failed = false

    var body: some View {
        Group {
            if let model {
                EditorView(model: model)
            } else if failed {
                ContentUnavailableView("Couldn't open this project", systemImage: "exclamationmark.triangle")
            } else {
                ProgressView()
            }
        }
        .task(id: projectID) {
            guard model == nil else { return }
            do {
                let project = try app.store.load(projectID)
                model = EditorModel(project: project, client: app.client, store: app.store)
            } catch {
                failed = true
            }
        }
    }
}
