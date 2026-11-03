import SwiftUI
import VoiceoverKit

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var key = ""
    @State private var status: Status = .idle

    private enum Status: Equatable {
        case idle, checking, valid
        case failed(String)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("xi-api-key", text: $key)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Save & verify", action: save)
                        .disabled(key.isEmpty || status == .checking)
                } header: {
                    Text("ElevenLabs API key")
                } footer: {
                    Text("Create a key at elevenlabs.io → Developers → API Keys. It is stored in the Keychain on this device only.")
                }

                statusSection

                if app.hasAPIKey {
                    Section {
                        Button("Remove key", role: .destructive) {
                            app.removeKey()
                            status = .idle
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        switch status {
        case .idle:
            if app.hasAPIKey {
                Label("A key is saved", systemImage: "key.fill")
            }
        case .checking:
            HStack { ProgressView(); Text("Checking key…") }
        case .valid:
            Label("Key works", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
        }
    }

    private func save() {
        status = .checking
        Task {
            do {
                try await app.saveAndVerify(key)
                key = ""
                status = .valid
            } catch {
                status = .failed(error.localizedDescription)
            }
        }
    }
}
