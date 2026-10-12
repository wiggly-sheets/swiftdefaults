import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var viewModel: SettingsViewModel

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            List(viewModel.filteredSettings) { setting in
                SettingRowView(setting: setting)
            }
            .searchable(text: $viewModel.searchText)
            .navigationTitle(viewModel.selectedCategory)
            .task {
                await viewModel.load()
            }
        }
    }
}
