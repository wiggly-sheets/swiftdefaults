import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var viewModel: SettingsViewModel
    @AppStorage("confirmReset") private var confirmReset = true
    @State private var isConfirmingReset = false

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            ZStack {
                List(viewModel.filteredSettings) { setting in
                    SettingRowView(setting: setting)
                }
                .disabled(viewModel.isApplying)
                .searchable(text: $viewModel.searchText)
                .navigationTitle(viewModel.selectedTitle)
                .task {
                    await viewModel.load()
                }
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        toolbarContent
                    }
                }
                .alert("Reset applied tweaks?", isPresented: $isConfirmingReset) {
                    Button("Reset", role: .destructive) {
                        Task { await viewModel.resetAll() }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Discard pending edits and restore every tweak this session applied.")
                }
                if viewModel.isLoading || viewModel.isApplying {
                    ProgressView()
                        .controlSize(.large)
                        .accessibilityLabel("Working")
                }
            }
            .alert(
                "Something went wrong",
                isPresented: Binding(
                    get: { viewModel.errorMessage != nil },
                    set: { presented in
                        if !presented {
                            viewModel.clearError()
                        }
                    }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
        .alert("Relaunch to finish", isPresented: Binding(
            get: { !viewModel.relaunchApps.isEmpty || viewModel.relaunchNeedsLogout },
            set: { presented in
                if !presented {
                    viewModel.dismissRelaunchPrompt()
                }
            }
        )) {
            Button("Relaunch Now") {
                Task { await viewModel.relaunchAppsNow() }
            }
            Button("Later", role: .cancel) {}
        } message: {
            Text(viewModel.relaunchMessage)
        }
    }

    @ViewBuilder
    private var toolbarContent: some View {
        if viewModel.hasPending {
            pendingLabel
        }
        resetButton
        applyButton
    }

    private var pendingLabel: some View {
        Text("\(viewModel.pendingValues.count) pending")
            .font(.caption)
            .monospacedDigit()
            .contentTransition(.numericText())
            .foregroundStyle(.secondary)
    }

    private var resetButton: some View {
        Button("Reset") {
            if confirmReset {
                isConfirmingReset = true
            } else {
                Task { await viewModel.resetAll() }
            }
        }
        .disabled(viewModel.isResetDisabled || viewModel.isApplying)
        .help("Discard pending edits and restore originals")
    }

    private var applyButton: some View {
        Button("Apply") {
            Task { await viewModel.applyPending() }
        }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.defaultAction)
        .disabled(!viewModel.hasPending || viewModel.isApplying)
        .help("Write all pending edits")
    }
}
