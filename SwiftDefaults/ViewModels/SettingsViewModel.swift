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
    @Published private(set) var pendingValues: [String: String] = [:]

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
        var groups: [(name: String, categories: [String])] = Self.categoryGroups.map { group in
            (group.name, group.categories.filter { present.contains($0) })
        }.filter { !$0.1.isEmpty }
        let grouped = Set(groups.flatMap(\.1))
        let ungrouped = present.subtracting(grouped).sorted()
        if !ungrouped.isEmpty {
            groups.append(("Other", ungrouped))
        }
        return groups
    }

    var filteredSettings: [DefaultSetting] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            if selectedCategory == "All" { return settings }
            return settings.filter { $0.category == selectedCategory }
        }
        return settings.filter { setting in
            setting.title.localizedCaseInsensitiveContains(query)
                || setting.description.localizedCaseInsensitiveContains(query)
                || setting.key.localizedCaseInsensitiveContains(query)
                || setting.category.localizedCaseInsensitiveContains(query)
                || setting.domain.localizedCaseInsensitiveContains(query)
                || setting.id.localizedCaseInsensitiveContains(query)
        }
    }

    func canRevert(_ setting: DefaultSetting) -> Bool {
        capturedIds.contains(setting.id)
    }

    var hasPending: Bool { !pendingValues.isEmpty }

    var canRevertAll: Bool { !capturedIds.isEmpty }

    var isResetDisabled: Bool { pendingValues.isEmpty && capturedIds.isEmpty }

    /// Display value: staged pending edit wins over last applied state.
    func stagedString(_ setting: DefaultSetting) -> String {
        pendingValues[setting.id]
            ?? currentValues[setting.id]
            ?? canonicalString(setting.offValue)
    }

    func stagedIsOn(_ setting: DefaultSetting) -> Bool {
        if let pending = pendingValues[setting.id] {
            return matchesOn(current: pending, onValue: setting.onValue)
        }
        return isOn[setting.id] ?? false
    }

    /// Stage a boolean edit locally; no disk write until applyPending.
    func stage(_ setting: DefaultSetting, on: Bool) {
        let staged = canonicalString(on ? setting.onValue : setting.offValue)
        if staged == currentValues[setting.id] {
            pendingValues.removeValue(forKey: setting.id)
        } else {
            pendingValues[setting.id] = staged
        }
    }

    /// Stage a non-boolean edit locally; validates without writing.
    func stageOption(_ setting: DefaultSetting, stringValue: String) {
        guard value(for: setting, stringValue: stringValue) != nil else {
            errorMessage = "Could not parse value for \(setting.id)"
            return
        }
        if stringValue == currentValues[setting.id] {
            pendingValues.removeValue(forKey: setting.id)
        } else {
            pendingValues[setting.id] = stringValue
        }
    }

    func discardPending() {
        pendingValues = [:]
    }

    /// Writes all staged edits, clears pending, keeps failures staged.
    @discardableResult
    func applyPending() async -> Bool {
        let staged = pendingValues
        guard !staged.isEmpty else { return true }
        var failed: [String: String] = [:]
        var lastError: String?
        for (id, stringValue) in staged {
            guard let setting = settings.first(where: { $0.id == id }) else { continue }
            guard let parsed = value(for: setting, stringValue: stringValue) else {
                failed[id] = stringValue
                lastError = "Could not parse value for \(id)"
                continue
            }
            await captureOriginal(setting)
            do {
                try await DefaultsEngine.write(parsed, for: setting)
                currentValues[id] = canonicalString(parsed)
                isOn[id] = matchesOn(current: stringValue, onValue: setting.onValue)
            } catch {
                failed[id] = stringValue
                lastError = error.localizedDescription
            }
        }
        pendingValues = failed
        errorMessage = lastError
        return failed.isEmpty
    }

    /// Discards pending edits, restores originals for applied tweaks.
    @discardableResult
    func resetAll() async -> Bool {
        pendingValues = [:]
        var ok = true
        for id in capturedIds {
            guard let setting = settings.first(where: { $0.id == id }) else { continue }
            if await revert(setting) == false { ok = false }
        }
        return ok
    }

    func load() async {
        guard settings.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            settings = try loadRegistry()
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clearError() {
        errorMessage = nil
    }

    func refresh() async {
        var newIsOn: [String: Bool] = [:]
        var newCurrent: [String: String] = [:]
        var lastError: String?
        let all = settings
        for offset in stride(from: 0, to: all.count, by: 8) {
            let chunk = Array(all[offset..<min(offset + 8, all.count)])
            await withTaskGroup(of: (String, String?, String?).self) { group in
                for setting in chunk {
                    group.addTask {
                        do {
                            let current = try await DefaultsEngine.read(domain: setting.domain, key: setting.key)
                            return (setting.id, current, nil)
                        } catch {
                            return (setting.id, nil, error.localizedDescription)
                        }
                    }
                }
                for await (id, current, readError) in group {
                    if let readError { lastError = readError }
                    guard let setting = all.first(where: { $0.id == id }) else { continue }
                    if let current {
                        newIsOn[id] = self.matchesOn(current: current, onValue: setting.onValue)
                        newCurrent[id] = current
                    } else {
                        newIsOn[id] = false
                        newCurrent[id] = self.canonicalString(setting.offValue)
                    }
                }
            }
        }
        isOn = newIsOn
        currentValues = newCurrent
        pendingValues = [:]
        if let lastError {
            errorMessage = lastError
        } else {
            errorMessage = nil
        }
    }

    @discardableResult
    func apply(_ setting: DefaultSetting, on: Bool) async -> Bool {
        await captureOriginal(setting)
        do {
            try await DefaultsEngine.write(on ? setting.onValue : setting.offValue, for: setting)
            isOn[setting.id] = on
            currentValues[setting.id] = canonicalString(on ? setting.onValue : setting.offValue)
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Writes a non-boolean value given its canonical string form.
    @discardableResult
    func applyOption(_ setting: DefaultSetting, stringValue: String) async -> Bool {
        guard let value = value(for: setting, stringValue: stringValue) else {
            errorMessage = "Could not parse value for \(setting.id)"
            return false
        }
        await captureOriginal(setting)
        do {
            try await DefaultsEngine.write(value, for: setting)
            currentValues[setting.id] = canonicalString(value)
            isOn[setting.id] = matchesOn(current: stringValue, onValue: setting.onValue)
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
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
    /// A custom original (e.g. tilesize 64) is parsed back and rewritten;
    /// defaultValue is only a fallback when parsing fails.
    @discardableResult
    func revert(_ setting: DefaultSetting) async -> Bool {
        guard capturedIds.contains(setting.id) else { return false }
        do {
            if let original = originalValues[setting.id],
               let parsed = value(for: setting, stringValue: original)
            {
                try await DefaultsEngine.write(parsed, for: setting)
                isOn[setting.id] = matchesOn(current: original, onValue: setting.onValue)
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
            errorMessage = nil
            pendingValues.removeValue(forKey: setting.id)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
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

    /// Numeric-aware comparison: `defaults read` prints 0.0 as "0".
    func matchesOn(current: String, onValue: SettingValue) -> Bool {
        switch onValue {
        case .boolean(let enabled):
            current == (enabled ? "1" : "0")
        case .integer(let number):
            Int(current) == number
        case .float(let number):
            Double(current) == number
        case .string(let text):
            current == text
        }
    }

    /// Canonical form matching `defaults read` output (booleans print as 1/0,
    /// whole floats print without the fraction: 0.0 reads back as "0").
    private func canonicalString(_ value: SettingValue) -> String {
        switch value {
        case .boolean(let enabled):
            enabled ? "1" : "0"
        case .integer(let number):
            String(number)
        case .string(let text):
            text
        case .float(let number):
            number == number.rounded() && number.isFinite ? String(Int(number)) : String(number)
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
