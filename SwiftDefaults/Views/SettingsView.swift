import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// App settings: profile transfer plus the behavior preferences the views read.
struct SettingsView: View {
    @EnvironmentObject private var viewModel: SettingsViewModel
    @AppStorage("showDescriptions") private var showDescriptions = true
    @AppStorage("confirmReset") private var confirmReset = true
    @State private var message: String?

    var body: some View {
        Form {
            Section("Profiles") {
                HStack {
                    Button("Export…") { exportProfile() }
                    Button("Import…") { importProfile() }
                    Spacer()
                }
                .disabled(viewModel.isApplying || viewModel.isLoading)
                Text("A profile holds the values this Mac has set, so another Mac running SwiftDefaults can import them. Importing stages the values; press Apply in the main window to write them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Display") {
                Toggle("Show setting descriptions", isOn: $showDescriptions)
            }
            Section("Safety") {
                Toggle("Ask before Reset reverts applied tweaks", isOn: $confirmReset)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .task {
            await viewModel.load()
        }
        .alert("Profile", isPresented: Binding(
            get: { message != nil },
            set: { presented in
                if !presented {
                    message = nil
                }
            }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
    }

    private func exportProfile() {
        let data: Data
        do {
            data = try viewModel.profileData()
        } catch {
            message = error.localizedDescription
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "SwiftDefaults Profile.json"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try data.write(to: url)
            } catch {
                message = error.localizedDescription
            }
        }
    }

    private func importProfile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let data = try Data(contentsOf: url)
                message = try viewModel.importProfile(data).summary
            } catch {
                message = error.localizedDescription
            }
        }
    }
}
