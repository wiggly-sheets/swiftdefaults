import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var viewModel: SettingsViewModel
    @State private var expandedGroups: Set<String> = ["System", "Input", "Apps"]
    /// Split categories start open, so this holds the ones the user closed.
    @State private var collapsedCategories: Set<String> = []

    var body: some View {
        List(selection: $viewModel.selectedCategory) {
            Label("All", systemImage: "square.grid.2x2")
                .tag(nil as String?)
            ForEach(viewModel.groupedCategories) { group in
                DisclosureGroup(isExpanded: groupBinding(for: group.name)) {
                    ForEach(group.categories) { category in
                        if category.subcategories.isEmpty {
                            Label(category.name, systemImage: icon(for: category.name))
                                .tag(category.name as String?)
                        } else {
                            DisclosureGroup(isExpanded: categoryBinding(for: category.name)) {
                                ForEach(category.subcategories) { subcategory in
                                    HStack {
                                        Text(subcategory.name)
                                        Spacer()
                                        Text("\(subcategory.count)")
                                            .foregroundStyle(.secondary)
                                    }
                                    .tag(category.name as String?)
                                }
                            } label: {
                                Label(category.name, systemImage: icon(for: category.name))
                            }
                        }
                    }
                } label: {
                    Text(group.name)
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func groupBinding(for group: String) -> Binding<Bool> {
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

    private func categoryBinding(for category: String) -> Binding<Bool> {
        Binding(
            get: { !collapsedCategories.contains(category) },
            set: { expanded in
                if expanded {
                    collapsedCategories.remove(category)
                } else {
                    collapsedCategories.insert(category)
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
            "cursorarrow.rays"
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
            "cursorarrow.click"
        case "Appearance":
            "paintpalette"
        case "Xcode":
            "hammer"
        case "TextEdit":
            "doc.text"
        case "Activity Monitor":
            "gauge.with.dots.needle.67percent"
        case "Safari":
            "safari"
        case "Feedback Assistant":
            "exclamationmark.bubble"
        case "Simulator":
            "iphone.gen3"
        case "Time Machine":
            "clock.arrow.trianglehead.counterclockwise.rotate.90"
        case "Messages":
            "message"
        case "Windows":
            "macwindow.on.rectangle"
        default:
            "square.grid.2x2"
        }
    }
}
