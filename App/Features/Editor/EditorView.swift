import PhotosUI
import SwiftUI
import VoiceoverKit

struct EditorView: View {
    @Bindable var model: EditorModel
    @Environment(AppModel.self) private var app

    @State var pickedItem: PhotosPickerItem?
    @State var isLoadingVideo = false
    @State var showsSettings = false
    @State var showsRecorder = false
    @State var showsPreview = false

    var body: some View {
        NavigationStack {
            Form {
                if !app.hasAPIKey {
                    apiKeyBanner
                }
                videoSection
                modeSection
                switch model.mode {
                case .type:
                    scriptSection
                case .record:
                    CharactersSection(project: model.project, client: model.client)
                    TakesSection(project: model.project) { model.delete($0) }
                }
                if model.player != nil {
                    MixSection(project: model.project) { model.applyMix() }
                }
                resultSection
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Voiceover Studio")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gearshape") { showsSettings = true }
                }
            }
            .safeAreaInset(edge: .bottom) { primaryButton }
            .sheet(isPresented: $showsSettings) { SettingsView() }
            .fullScreenCover(isPresented: $showsRecorder) { RecordingView(model: model) }
            .fullScreenCover(isPresented: $showsPreview) {
                if let player = model.player {
                    PreviewScreen(player: player, captions: model.captions)
                }
            }
            .alert(item: $model.failure) { failure in
                failureAlert(failure)
            }
            .onChange(of: pickedItem) { _, item in loadVideo(item) }
            .task { await loadDebugVideo() }
        }
    }

    /// Development aid: `VOICEOVER_DEBUG_VIDEO=/path/to.mov` loads a video and opens the recorder on launch,
    /// so the recording screen can be exercised on a simulator without going through Photos.
    private func loadDebugVideo() async {
        #if DEBUG
        guard let path = ProcessInfo.processInfo.environment["VOICEOVER_DEBUG_VIDEO"], model.videoURL == nil else { return }
        await model.setVideo(URL(fileURLWithPath: path))
        showsRecorder = true
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

    private var videoSection: some View {
        // PhotosPicker's label closure is nonisolated, so read main-actor state up front.
        let hasVideo = model.videoURL != nil
        let isLoading = isLoadingVideo
        let duration = model.videoDuration
        return Section("Video") {
            PhotosPicker(selection: $pickedItem, matching: .videos, preferredItemEncoding: .current) {
                HStack {
                    Label(hasVideo ? "Replace video" : "Choose a video", systemImage: "film")
                    Spacer()
                    if isLoading {
                        ProgressView()
                    } else if hasVideo {
                        Text(Duration.seconds(duration).formatted(.time(pattern: .minuteSecond)))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
        }
    }

    private var modeSection: some View {
        Section {
            Picker("Mode", selection: $model.mode) {
                Text("Record").tag(EditorModel.Mode.record)
                Text("Type").tag(EditorModel.Mode.type)
            }
            .pickerStyle(.segmented)
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
            NavigationLink {
                VoicePickerView(client: model.client, selection: $model.voice)
            } label: {
                LabeledContent("Voice", value: model.voice?.name ?? "Choose")
            }
        } header: {
            Text("Voiceover")
        } footer: {
            Text("\(model.script.count) characters. Each character uses one ElevenLabs credit.")
        }
    }

    @ViewBuilder
    private var resultSection: some View {
        if let player = model.player {
            Section(model.mode == .type ? "Preview" : "Export") {
                // Record mode has the full-screen recorder for playback; a second player here only confused.
                if model.mode == .type {
                    PreviewPlayer(player: player, captions: model.captions)
                        .aspectRatio(9 / 16, contentMode: .fit)
                        .frame(maxHeight: 460)
                        .listRowInsets(EdgeInsets())
                }

                if !model.hasResult {
                    Text(model.mode == .type ? "Generate a voiceover to export." : "Record a take to export.")
                        .foregroundStyle(.secondary)
                } else if model.mode == .record {
                    Button("Preview", systemImage: "play.rectangle") { showsPreview = true }
                }
                if !model.hasResult {
                    EmptyView()
                } else if let url = model.exportedURL {
                    ShareLink(item: url) {
                        Label("Share or save video", systemImage: "square.and.arrow.up")
                    }
                } else {
                    Button("Export with captions", systemImage: "square.and.arrow.down") { model.export() }
                        .disabled(model.activity != nil)
                }
            }
        }
    }

    // MARK: - Bottom bar

    private var primaryButton: some View {
        Group {
            if model.isRecording {
                Button {
                    model.stopRecording()
                } label: {
                    Label("Stop", systemImage: "stop.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.large)
            } else if let activity = model.activity {
                HStack(spacing: 12) {
                    ProgressView()
                    Text(activityTitle(activity))
                    Spacer()
                    Button("Cancel", role: .cancel) { model.cancel() }
                }
            } else {
                switch model.mode {
                case .record:
                    HStack(spacing: 12) {
                        Button {
                            showsRecorder = true
                        } label: {
                            Label(recordTitle, systemImage: "record.circle").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .disabled(model.player == nil)

                        if model.canSwapVoices {
                            Button {
                                model.swapVoices()
                            } label: {
                                Label(swapTitle, systemImage: "arrow.triangle.2.circlepath")
                            }
                            .buttonStyle(.bordered)
                            .disabled(!app.hasAPIKey)
                        }
                    }
                    .controlSize(.large)
                case .type:
                    Button {
                        model.generate()
                    } label: {
                        Label(model.hasResult ? "Regenerate" : "Generate voiceover", systemImage: "waveform")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!model.canGenerate || !app.hasAPIKey)
                }
            }
        }
        .padding()
        .background(.bar)
    }

    /// Shows what a swap will cost: ElevenLabs bills speech-to-speech by audio length.
    private var swapTitle: String {
        let seconds = Int(model.project.secondsNeedingConversion.rounded(.up))
        return "Swap voices · \(seconds) s"
    }

    private var recordTitle: String {
        model.project.takes.isEmpty ? "Record takes" : "Record more"
    }

    private func activityTitle(_ activity: EditorModel.Activity) -> String {
        switch activity {
        case .generating: "Generating voice…"
        case .generatingEffect: "Generating sound effect…"
        case .composing: "Updating preview…"
        case .exporting: "Exporting…"
        case .swapping: "Swapping voices…"
        }
    }
}
