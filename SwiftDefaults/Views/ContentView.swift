import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var viewModel: SettingsViewModel
    @State private var isApplying = false

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            ZStack {
                List(viewModel.filteredSettings) { setting in
                    SettingRowView(setting: setting)
                }
                .searchable(text: $viewModel.searchText)
                .navigationTitle(viewModel.selectedCategory)
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
                            Task { @MainActor in
                                isApplying = true
                                defer { isApplying = false }
                                await viewModel.resetAll()
                            }
                        }
                        .disabled(viewModel.isResetDisabled || isApplying)
                        .help("Discard pending edits and restore originals")
                        Button("Apply") {
                            Task { @MainActor in
                                isApplying = true
                                defer { isApplying = false }
                                await viewModel.applyPending()
                            }
                        }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!viewModel.hasPending || isApplying)
                        .help("Write all pending edits")
                    }
                }
                if viewModel.isLoading || isApplying {
                    ProgressView()
                        .controlSize(.large)
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
