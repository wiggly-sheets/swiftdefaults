import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var viewModel: SettingsViewModel
    @Namespace private var toolbarNamespace

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
                .navigationTitle(viewModel.selectedCategory ?? "All")
                .task {
                    await viewModel.load()
                }
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        toolbarContent
                    }
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
    }

    @ViewBuilder
    private var toolbarContent: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 8) {
                if viewModel.hasPending {
                    pendingLabel
                }
                resetButton
                    .glassEffectID("reset", in: toolbarNamespace)
                applyButton
                    .glassEffectID("apply", in: toolbarNamespace)
            }
        } else {
            if viewModel.hasPending {
                pendingLabel
            }
            resetButton
            applyButton
        }
    }

    private var pendingLabel: some View {
        Text("\(viewModel.pendingValues.count) pending")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private var resetButton: some View {
        Button("Reset") {
            Task { await viewModel.resetAll() }
        }
        .disabled(viewModel.isResetDisabled || viewModel.isApplying)
        .help("Discard pending edits and restore originals")
    }

    private var applyButton: some View {
        Button("Apply") {
            Task { await viewModel.applyPending() }
        }
        .keyboardShortcut(.defaultAction)
        .disabled(!viewModel.hasPending || viewModel.isApplying)
        .help("Write all pending edits")
    }
}
