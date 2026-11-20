import PhotosUI
import SwiftUI
import VoiceoverKit

struct EditorView: View {
    /// The full-screen modes of the editor. One optional value, so two can never be up at once.
    enum Cover: String, Identifiable {
        case recorder, preview
        var id: String { rawValue }
    }

    /// What the lower half of the screen is working on. The stage above stays the same for all three.
    enum Tool: Hashable {
        case voice, sounds, music
    }

    @Bindable var model: EditorModel
    // Not private: the bottom bar in `EditorView+BottomBar` reads it.
    @Environment(AppModel.self) var app

    @State var pickedItem: PhotosPickerItem?
    @State var isLoadingVideo = false
    @State var showsSettings = false
    @State var showsSoundIdeas = false
    @State var showsVideoPicker = false
    @State var cover: Cover?
    @State var tool = Tool.voice
    @Namespace private var previewSource
    @State private var keyboardIsUp = false

    var body: some View {
        VStack(spacing: 0) {
            // Pinned: the rest of the screen is about this picture.
            EditorStage(
                model: model,
                isLoading: isLoadingVideo,
                isCompact: keyboardIsUp,
                previewSource: previewSource,
                onPickVideo: { showsVideoPicker = true },
                onExpand: { cover = .preview }
            )
            // Sounds and music are laid over a video; until there is one, only the voice tools make sense.
            if model.player != nil {
                toolPicker
            }

            Form {
                if !app.hasAPIKey {
                    apiKeyBanner
                }
                resultSection

                switch model.player == nil ? Tool.voice : tool {
                case .voice:
                    modeSection
                    switch model.mode {
                    case .type:
                        scriptSection
                    case .record:
                        CharactersSection(model: model)
                        TakesSection(project: model.project, canEdit: !model.isBusy) { model.delete($0) }
                    }
                case .sounds:
                    SoundIdeasSection(model: model) { showsSoundIdeas = true }
                    EffectsSection(model: model)
                case .music:
                    MusicSection(model: model, hasAPIKey: app.hasAPIKey)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .contentMargins(.top, 8, for: .scrollContent)
            .listSectionSpacing(.compact)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(model.project.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Settings", systemImage: "gearshape") { showsSettings = true }
            }
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
            ToolbarItem(placement: .topBarTrailing) {
                // Where editors keep it: the result of the screen, always one tap away.
                Button(model.exportedURL == nil ? "Export with captions" : "Export again", systemImage: "square.and.arrow.up") {
                    model.export()
                }
                .disabled(!model.hasResult || model.activity != nil)
            }
        }
        .safeAreaInset(edge: .bottom) { primaryButton }
        .photosPicker(
            isPresented: $showsVideoPicker, selection: $pickedItem, matching: .videos, preferredItemEncoding: .current
        )
        .sheet(isPresented: $showsSettings) { SettingsView() }
        .sheet(isPresented: $showsSoundIdeas) { SoundIdeasSheet(model: model, hasAPIKey: app.hasAPIKey) }
        .animation(.easeOut(duration: 0.25), value: keyboardIsUp)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { note in
            // With a hardware keyboard the system still "shows" one: a bar a few points tall that covers nothing.
            let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
            keyboardIsUp = (frame?.height ?? 0) > 120
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardIsUp = false
        }
        .onChange(of: cover) { _, cover in
            // The recorder drives the same player from its own transport; it must not open onto a running video.
            if cover == .recorder { model.player?.pause() }
        }
        .fullScreenCover(item: $cover) { cover in
            switch cover {
            case .recorder:
                RecordingView(model: model)
            case .preview:
                // Grows out of the stage's picture instead of sliding up over it.
                EditPreview(model: model)
                    .navigationTransition(.zoom(sourceID: EditorStage.previewID, in: previewSource))
            }
        }
        .navigationDestination(for: EditorRoute.self) { route in
            switch route {
            case .voice(let target):
                VoicePickerView(client: model.client, selection: voiceBinding(target))
            }
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(get: { model.failure != nil }, set: { if !$0 { model.failure = nil } }),
            presenting: model.failure,
            actions: failureActions,
            message: { failure in Text(failure.message) }
        )
        .onChange(of: pickedItem) { _, item in loadVideo(item) }
        .task { await loadDebugVideo() }
    }

    /// Development aid: `VOICEOVER_DEBUG_VIDEO=/path/to.mov` loads a video and opens the recorder on launch,
    /// so the recording screen can be exercised on a simulator without going through Photos.
    private func loadDebugVideo() async {
        #if DEBUG
        guard let path = ProcessInfo.processInfo.environment["VOICEOVER_DEBUG_VIDEO"], model.videoURL == nil else { return }

        await model.setVideo(URL(fileURLWithPath: path))
        cover = .recorder
        #endif
    }

    // MARK: - Sections

    private var apiKeyBanner: some View {
        Section {
            Button {
                showsSettings = true
            } label: {
                Label("Add your ElevenLabs API key to start", systemImage: "key")
            }
        }
    }

    private var toolPicker: some View {
        Picker("Tools", selection: $tool) {
            Label("Voice", systemImage: "person.wave.2")
                .tag(Tool.voice)
            Label("Sounds", systemImage: "sparkles")
                .tag(Tool.sounds)
            Label("Music", systemImage: "music.note")
                .tag(Tool.music)
        }
        .pickerStyle(.segmented)
        .labelStyle(.titleOnly)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 2)
    }

    private var modeSection: some View {
        Section {
            Picker("Mode", selection: $model.mode) {
                Text("Record")
                    .tag(EditorModel.Mode.record)
                Text("Type")
                    .tag(EditorModel.Mode.type)
            }
            .pickerStyle(.segmented)
            .disabled(model.isBusy)
        } footer: {
            Text(model.mode == .record
                ? "Speak over the video in your own voice, then swap it for an ElevenLabs voice."
                : "Write a script and let an ElevenLabs voice read it.")
        }
    }

    private var scriptSection: some View {
        Section {
            TextField("What should the voice say?", text: $model.script, axis: .vertical)
                .lineLimit(3...8)
            NavigationLink(value: EditorRoute.voice(.script)) {
                LabeledContent("Voice", value: model.voice?.name ?? String(localized: "Choose"))
            }
        } header: {
            Text("Voiceover")
        } footer: {
            Text("\(model.script.count) characters. Each character uses one ElevenLabs credit.")
        }
    }

    /// What the last export left, and the range the next one covers. Sits right under the stage so the
    /// outcome of Export is seen without scrolling; empty (and absent) until there is something to say.
    @ViewBuilder
    private var resultSection: some View {
        if model.hasResult, model.exportedURL != nil || model.project.isTrimmed {
            Section {
                if model.project.isTrimmed {
                    let range = model.project.trimRange
                    LabeledContent("Export range") {
                        Text("\(timecode(range.lowerBound)) – \(timecode(range.upperBound))")
                            .monospacedDigit()
                    }
                }
                if let url = model.exportedURL {
                    if model.savedToPhotos {
                        Label("Saved to Photos", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("Save to Photos", systemImage: "photo.badge.plus") { model.saveToPhotos() }
                            .disabled(model.activity != nil)
                    }
                    ShareLink(item: url) {
                        Label("Share…", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
    }

    private func timecode(_ seconds: Double) -> String {
        Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond(padMinuteToLength: 1, fractionalSecondsLength: 1)))
    }
}

#Preview("New project") {
    let app = AppModel.preview()
    NavigationStack {
        EditorView(model: app.editor(for: app.store.create()))
    }
    .environment(app)
}
