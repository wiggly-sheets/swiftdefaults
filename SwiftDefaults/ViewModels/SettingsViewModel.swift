import Foundation

enum RegistryError: Error, LocalizedError {
    case missingFile

    var errorDescription: String? {
        "Could not find tweaks.json in the app bundle."
    }
}

/// Loads the JSON registry, tracks live state, applies and reverts tweaks.
@MainActor
final class SettingsViewModel: ObservableObject {
    @Published private(set) var settings: [DefaultSetting] = []
    @Published private(set) var isOn: [String: Bool] = [:]
    @Published private(set) var currentValues: [String: String] = [:]
    @Published var selectedCategory = "All"
    @Published var searchText = ""
    @Published private(set) var errorMessage: String?
    @Published private(set) var isLoading = false

    private var originalValues: [String: String] = [:]
    private var capturedIds: Set<String> = []

    var categories: [String] {
        ["All"] + Set(settings.map(\.category)).sorted()
    }

    private static let categoryGroups: [(name: String, categories: [String])] = [
        ("System", ["Appearance", "Desktop", "Dock", "Finder", "Menu Bar", "Screenshots", "Window Manager", "Mission Control", "Miscellaneous", "Windows"]),
        ("Input", ["Keyboard", "Trackpad", "Mouse"]),
        ("Apps", ["Xcode", "TextEdit", "Safari", "Activity Monitor", "Feedback Assistant", "Simulator", "Time Machine", "Messages"]),
    ]

    var groupedCategories: [(name: String, categories: [String])] {
        let present = Set(settings.map(\.category))
        return Self.categoryGroups.map { group in
            (group.name, group.categories.filter { present.contains($0) })
        }.filter { !$0.categories.isEmpty }
    }

    var filteredSettings: [DefaultSetting] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return settings.filter { setting in
            let matchesCategory = selectedCategory == "All" || setting.category == selectedCategory
            let matchesSearch = query.isEmpty
                || setting.title.localizedCaseInsensitiveContains(query)
                || setting.description.localizedCaseInsensitiveContains(query)
                || setting.key.localizedCaseInsensitiveContains(query)
            return matchesCategory && matchesSearch
        }
    }

    func canRevert(_ setting: DefaultSetting) -> Bool {
        capturedIds.contains(setting.id)
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            settings = try loadRegistry()
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refresh() async {
        for setting in settings {
            do {
                if let current = try await DefaultsEngine.read(domain: setting.domain, key: setting.key) {
                    isOn[setting.id] = (current == canonicalString(setting.onValue))
                    currentValues[setting.id] = current
                } else {
                    isOn[setting.id] = false
                    currentValues[setting.id] = canonicalString(setting.offValue)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func apply(_ setting: DefaultSetting, on: Bool) async {
        await captureOriginal(setting)
        do {
            try await DefaultsEngine.write(on ? setting.onValue : setting.offValue, for: setting)
            isOn[setting.id] = on
            currentValues[setting.id] = canonicalString(on ? setting.onValue : setting.offValue)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Writes a non-boolean value given its canonical string form.
    func applyOption(_ setting: DefaultSetting, stringValue: String) async {
        guard let value = value(for: setting, stringValue: stringValue) else {
            errorMessage = "Could not parse value for \(setting.id)"
            return
        }
        await captureOriginal(setting)
        do {
            try await DefaultsEngine.write(value, for: setting)
            currentValues[setting.id] = stringValue
            isOn[setting.id] = (stringValue == canonicalString(setting.onValue))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Canonical form matching `defaults read` output (booleans print as 1/0).
    func displayString(_ value: SettingValue) -> String {
        canonicalString(value)
    }

    private func value(for setting: DefaultSetting, stringValue: String) -> SettingValue? {
        switch setting.type {
        case .boolean:
            if stringValue == "1" { return .boolean(true) }
            if stringValue == "0" { return .boolean(false) }
            return nil
        case .integer:
            guard let number = Int(stringValue) else { return nil }
            return .integer(number)
        case .string:
            return .string(stringValue)
        case .float:
            guard let number = Double(stringValue) else { return nil }
            return .float(number)
        }
    }

    /// Restores the value present before the first apply.
    /// Deletes the key when it did not exist, restoring the system default.
    func revert(_ setting: DefaultSetting) async {
        guard capturedIds.contains(setting.id) else { return }
        do {
            if let original = originalValues[setting.id] {
                if original == canonicalString(setting.onValue) {
                    try await DefaultsEngine.write(setting.onValue, for: setting)
                    isOn[setting.id] = true
                    currentValues[setting.id] = original
                } else if original == canonicalString(setting.offValue) {
                    try await DefaultsEngine.write(setting.offValue, for: setting)
                    isOn[setting.id] = false
                    currentValues[setting.id] = original
                } else if let fallback = setting.defaultValue {
                    try await DefaultsEngine.write(fallback, for: setting)
                    isOn[setting.id] = (fallback == setting.onValue)
                    currentValues[setting.id] = canonicalString(fallback)
                } else {
                    try await DefaultsEngine.delete(domain: setting.domain, key: setting.key)
                    isOn[setting.id] = false
                    currentValues[setting.id] = canonicalString(setting.offValue)
                }
            } else {
                try await DefaultsEngine.delete(domain: setting.domain, key: setting.key)
                isOn[setting.id] = false
                currentValues[setting.id] = canonicalString(setting.offValue)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func captureOriginal(_ setting: DefaultSetting) async {
        guard !capturedIds.contains(setting.id) else { return }
        capturedIds.insert(setting.id)
        do {
            if let current = try await DefaultsEngine.read(domain: setting.domain, key: setting.key) {
                originalValues[setting.id] = current
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Canonical form matching `defaults read` output (booleans print as 1/0).
    private func canonicalString(_ value: SettingValue) -> String {
        switch value {
        case .boolean(let enabled):
            enabled ? "1" : "0"
        case .integer(let number):
            String(number)
        case .string(let text):
            text
        case .float(let number):
            String(number)
        }
    }

    private func loadRegistry() throws -> [DefaultSetting] {
        #if SWIFT_PACKAGE
        let bundles = [Bundle.module, Bundle.main]
        #else
        let bundles = [Bundle.main]
        #endif
        for bundle in bundles {
            if let url = bundle.url(forResource: "tweaks", withExtension: "json") {
                let data = try Data(contentsOf: url)
                return try JSONDecoder().decode([DefaultSetting].self, from: data)
            }
        }
        throw RegistryError.missingFile
    }
}
