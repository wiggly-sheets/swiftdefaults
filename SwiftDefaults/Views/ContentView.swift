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
                .searchable(text: $viewModel.searchText)
                .navigationTitle(viewModel.selectedCategory)
                .task {
                    await viewModel.load()
                }
                if viewModel.isLoading {
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
