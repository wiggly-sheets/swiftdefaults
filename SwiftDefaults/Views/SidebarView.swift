import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var viewModel: SettingsViewModel
    @State private var expandedGroups: Set<String> = ["System", "Input", "Apps"]

    var body: some View {
        List(selection: $viewModel.selectedCategory) {
            Label("All", systemImage: "square.grid.2x2")
                .tag("All")
            ForEach(viewModel.groupedCategories, id: \.name) { group in
                DisclosureGroup(isExpanded: binding(for: group.name)) {
                    ForEach(group.categories, id: \.self) { category in
                        Label(category, systemImage: icon(for: category))
                            .tag(category)
                    }
                } label: {
                    Text(group.name)
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func binding(for group: String) -> Binding<Bool> {
        Binding(
            get: { expandedGroups.contains(group) },
            set: { expanded in
                if expanded {
                    expandedGroups.insert(group)
                } else {
                    expandedGroups.remove(group)
                }
            }
        )
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
        case "Desktop":
            "desktopcomputer"
        case "Keyboard":
            "keyboard"
        case "Miscellaneous":
            "squareshape.squareshape.dashed"
        case "Window Manager":
            "macwindow"
        case "Mission Control":
            "square.grid.3x3"
        case "Mouse":
            "mouse"
        case "Appearance":
            "paintpalette"
        case "Xcode":
            "hammer"
        case "TextEdit":
            "doc.text"
        case "Activity Monitor":
            "gauge.with.dots.needle.67percent"
        case "Safari":
            "compass"
        case "Feedback Assistant":
            "exclamationmark.bubble"
        case "Simulator":
            "iphone.gen3"
        case "Time Machine":
            "clock.arrow.trianglehead.counterclockwise.rotate.90"
        case "Messages":
            "message"
        case "Windows":
            "app.window.group"
        default:
            "square.grid.2x2"
        }
    }
}
