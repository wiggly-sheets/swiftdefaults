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
                    pendingChip
                        .glassEffectID("pending", in: toolbarNamespace)
                        .glassEffectTransition(.matchedGeometry)
                }
                resetButton
                    .buttonStyle(.glass)
                    .glassEffectID("reset", in: toolbarNamespace)
                applyButton
                    .buttonStyle(.glassProminent)
                    .glassEffectID("apply", in: toolbarNamespace)
            }
            .animation(.smooth(duration: 0.25), value: viewModel.hasPending)
            .animation(.smooth(duration: 0.25), value: viewModel.pendingValues.count)
        } else {
            if viewModel.hasPending {
                pendingLabel
            }
            resetButton
            applyButton
        }
    }

    /// The pending count sits on its own glass capsule, so it can morph into the
    /// Apply button as edits appear and disappear.
    @available(macOS 26.0, *)
    private var pendingChip: some View {
        pendingLabel
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .glassEffect(.regular, in: .capsule)
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
