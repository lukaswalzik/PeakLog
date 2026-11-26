import SwiftUI

struct MistralSettingsView: View {
    @ObservedObject private var mistral = MistralAIService.shared

    @State private var isTesting: Bool = false
    @State private var testStatusMessage: String? = nil
    @State private var testSucceeded: Bool = false
    @State private var showKeyPlaintext: Bool = false

    var body: some View {
        Form {
            Section(
                header: Text("Mistral API-Key"),
                footer: Text("Dein API-Key wird ausschließlich lokal auf deinem iPhone gespeichert und niemals an Dritte oder GitHub gesendet.")
            ) {
                HStack {
                    if showKeyPlaintext {
                        TextField("Mistral API-Key einfügen", text: $mistral.apiKey)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } else {
                        SecureField("Mistral API-Key einfügen", text: $mistral.apiKey)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }

                    Button {
                        showKeyPlaintext.toggle()
                    } label: {
                        Image(systemName: showKeyPlaintext ? "eye.slash" : "eye")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    runConnectionTest()
                } label: {
                    HStack {
                        if isTesting {
                            ProgressView()
                                .padding(.trailing, 4)
                            Text("Teste Verbindung...")
                        } else {
                            Label("Verbindung testen", systemImage: "antenna.radiowaves.left.and.right")
                        }
                    }
                }
                .disabled(isTesting || !mistral.isConfigured)

                if let msg = testStatusMessage {
                    HStack(spacing: 8) {
                        Image(systemName: testSucceeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundColor(testSucceeded ? .green : .orange)
                        Text(msg)
                            .font(.caption)
                            .foregroundColor(testSucceeded ? .green : .orange)
                    }
                }
            }

            Section(header: Text("Modell")) {
                Picker("Mistral Modell", selection: $mistral.selectedModel) {
                    ForEach(MistralModel.allCases) { model in
                        Text(model.displayName).tag(model)
                    }
                }
                Text(mistral.selectedModel.shortSubtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section(header: Text("Wo bekomme ich meinen Key?")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("1. Öffne **console.mistral.ai** im Browser und melde dich mit deinem Mistral-Student-Account an.")
                    Text("2. Gehe links auf **API Keys** → **Create new key**.")
                    Text("3. Kopiere den Key und füge ihn oben ein – danach auf **Verbindung testen** tippen.")
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Mistral KI-Einstellungen")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func runConnectionTest() {
        isTesting = true
        testStatusMessage = nil
        Task {
            do {
                let message = try await mistral.testConnection()
                await MainActor.run {
                    testSucceeded = true
                    testStatusMessage = message
                    isTesting = false
                }
            } catch {
                await MainActor.run {
                    testSucceeded = false
                    testStatusMessage = error.localizedDescription
                    isTesting = false
                }
            }
        }
    }
}
