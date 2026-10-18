import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var viewModel: SettingsViewModel

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
                        if viewModel.hasPending {
                            Text("\(viewModel.pendingValues.count) pending")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Button("Reset") {
                            Task { await viewModel.resetAll() }
                        }
                        .disabled(viewModel.isResetDisabled || viewModel.isApplying)
                        .help("Discard pending edits and restore originals")
                        Button("Apply") {
                            Task { await viewModel.applyPending() }
                        }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!viewModel.hasPending || viewModel.isApplying)
                        .help("Write all pending edits")
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
}
