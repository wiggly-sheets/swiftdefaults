import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var viewModel: SettingsViewModel

    var body: some View {
        List(viewModel.categories, id: \.self, selection: $viewModel.selectedCategory) { category in
            Label(category, systemImage: icon(for: category))
        }
        .listStyle(.sidebar)
    }

    private func icon(for category: String) -> String {
        switch category {
        case "Finder":
            "folder"
        case "Dock":
            "dock.rectangle"
        case "Screenshots":
            "camera"
        case "Menu Bar":
            "menubar.rectangle"
        case "Trackpad":
            "trackpad"
        default:
            "square.grid.2x2"
        }
    }
}
