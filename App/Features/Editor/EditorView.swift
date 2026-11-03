import PhotosUI
import SwiftUI
import VoiceoverKit

struct EditorView: View {
    @Bindable var model: EditorModel
    @Environment(AppModel.self) private var app

    @State private var pickedItem: PhotosPickerItem?
    @State private var isLoadingVideo = false
    @State private var showsSettings = false

    var body: some View {
        NavigationStack {
            Form {
                if !app.hasAPIKey {
                    apiKeyBanner
                }
                videoSection
                scriptSection
                effectSection
                resultSection
            }
            .navigationTitle("Voiceover Studio")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gearshape") { showsSettings = true }
                }
            }
            .safeAreaInset(edge: .bottom) { primaryButton }
            .sheet(isPresented: $showsSettings) { SettingsView() }
            .alert(item: $model.failure) { failure in
                failureAlert(failure)
            }
            .onChange(of: pickedItem) { _, item in loadVideo(item) }
        }
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

    private var effectSection: some View {
        Section {
            TextField("e.g. distant thunder, crowd cheering", text: $model.effectPrompt)
            if model.videoDuration > 0 {
                VStack(alignment: .leading) {
                    LabeledContent("Starts at", value: model.effectStart.formatted(.number.precision(.fractionLength(1))) + " s")
                    Slider(value: $model.effectStart, in: 0...model.videoDuration) { editing in
                        if !editing { model.applyEffectStart() }
                    }
                }
            }
        } header: {
            Text("Sound effect (optional)")
        }
    }

    @ViewBuilder
    private var resultSection: some View {
        if let player = model.player {
            Section("Preview") {
                PreviewPlayer(player: player, captions: model.captions)
                    .aspectRatio(9 / 16, contentMode: .fit)
                    .frame(maxHeight: 460)
                    .listRowInsets(EdgeInsets())

                if let url = model.exportedURL {
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
            if let activity = model.activity {
                HStack(spacing: 12) {
                    ProgressView()
                    Text(activityTitle(activity))
                    Spacer()
                    Button("Cancel", role: .cancel) { model.cancel() }
                }
            } else {
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
        .padding()
        .background(.bar)
    }

    private func activityTitle(_ activity: EditorModel.Activity) -> String {
        switch activity {
        case .generating: "Generating voice…"
        case .composing: "Updating preview…"
        case .exporting: "Exporting…"
        }
    }

    // MARK: - Helpers

    private func loadVideo(_ item: PhotosPickerItem?) {
        guard let item else { return }
        isLoadingVideo = true
        Task {
            defer { isLoadingVideo = false }
            do {
                if let movie = try await item.loadTransferable(type: PickedMovie.self) {
                    await model.setVideo(movie.url)
                }
            } catch {
                model.failure = .init(message: "Couldn't load this video.", recovery: .none)
            }
        }
    }

    private func failureAlert(_ failure: EditorModel.Failure) -> Alert {
        switch failure.recovery {
        case .openSettings:
            Alert(
                title: Text("Something went wrong"),
                message: Text(failure.message),
                primaryButton: .default(Text("Open Settings")) { showsSettings = true },
                secondaryButton: .cancel()
            )
        case .retry:
            Alert(
                title: Text("Something went wrong"),
                message: Text(failure.message),
                primaryButton: .default(Text("Retry")) { failure.retry?() },
                secondaryButton: .cancel()
            )
        case .editInput, .none:
            Alert(title: Text("Something went wrong"), message: Text(failure.message))
        }
    }
}
