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
    @Published var selectedCategory = "All"
    @Published var searchText = ""
    @Published private(set) var errorMessage: String?
    @Published private(set) var isLoading = false

    private var originalValues: [String: String] = [:]
    private var capturedIds: Set<String> = []

    var categories: [String] {
        ["All"] + Set(settings.map(\.category)).sorted()
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
                } else {
                    isOn[setting.id] = false
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
        } catch {
            errorMessage = error.localizedDescription
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
                } else if original == canonicalString(setting.offValue) {
                    try await DefaultsEngine.write(setting.offValue, for: setting)
                    isOn[setting.id] = false
                } else if let fallback = setting.defaultValue {
                    try await DefaultsEngine.write(fallback, for: setting)
                    isOn[setting.id] = (fallback == setting.onValue)
                } else {
                    try await DefaultsEngine.delete(domain: setting.domain, key: setting.key)
                    isOn[setting.id] = false
                }
            } else {
                try await DefaultsEngine.delete(domain: setting.domain, key: setting.key)
                isOn[setting.id] = false
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
        guard let url = Bundle.main.url(forResource: "tweaks", withExtension: "json") else {
            throw RegistryError.missingFile
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([DefaultSetting].self, from: data)
    }
}
