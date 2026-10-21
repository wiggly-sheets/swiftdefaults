import Combine
import Foundation

enum RegistryError: Error, LocalizedError {
    case missingFile
    case invalidEntry(String)
    case duplicate(String)

    var errorDescription: String? {
        switch self {
        case .missingFile:
            "Could not find tweaks.json in the app bundle."
        case .invalidEntry(let detail):
            "Invalid registry entry: \(detail)"
        case .duplicate(let detail):
            "Duplicate registry entry: \(detail)"
        }
    }
}

/// One subcategory section of a split category, with the item count the sidebar shows.
struct Subcategory: Identifiable, Sendable {
    let name: String
    let count: Int

    var id: String { name }
}

/// One sidebar category. `subcategories` is empty when the category stays flat.
struct Category: Identifiable, Sendable {
    let name: String
    let subcategories: [Subcategory]

    var id: String { name }
}

/// A sidebar section holding categories.
struct CategoryGroup: Identifiable, Sendable {
    let name: String
    let categories: [Category]

    var id: String { name }
}

/// Loads the JSON registry, tracks live state, applies and reverts tweaks.
@MainActor
final class SettingsViewModel: ObservableObject {
    @Published private(set) var settings: [DefaultSetting] = []
    @Published private(set) var isOn: [String: Bool] = [:]
    @Published private(set) var currentValues: [String: String] = [:]
    @Published var selectedCategory: String?
    @Published var searchText = ""
    @Published private(set) var errorMessage: String?
    @Published private(set) var isLoading = false
    @Published private(set) var pendingValues: [String: String] = [:]
    /// In-flight apply, reset or single revert. Set by the view model itself so every
    /// entry point takes part in the same re-entry guard.
    @Published private(set) var isApplying = false

    /// Parsed values read at load. Ids in `capturedIds` with no entry here were absent on disk.
    private var originalValues: [String: SettingValue] = [:]
    private var capturedIds: Set<String> = []
    /// Ids this session actually wrote, i.e. the only ones a revert can undo.
    private var appliedIds: Set<String> = []

    private static let categoryGroups: [(name: String, categories: [String])] = [
        ("System", ["Appearance", "Desktop", "Dock", "Finder", "Menu Bar", "Screenshots", "Window Manager", "Mission Control", "Miscellaneous", "Windows"]),
        ("Input", ["Keyboard", "Trackpad", "Mouse"]),
        ("Apps", ["Xcode", "TextEdit", "Safari", "Activity Monitor", "Feedback Assistant", "Simulator", "Time Machine", "Messages"]),
    ]

    var groupedCategories: [CategoryGroup] {
        let present = Set(settings.map(\.category))
        var groups = Self.categoryGroups.map { group in
            CategoryGroup(
                name: group.name,
                categories: group.categories.filter { present.contains($0) }.map(node(for:))
            )
        }.filter { !$0.categories.isEmpty }
        let grouped = Set(groups.flatMap { $0.categories.map(\.name) })
        let ungrouped = present.subtracting(grouped).sorted()
        if !ungrouped.isEmpty {
            groups.append(CategoryGroup(name: "Other", categories: ungrouped.map(node(for:))))
        }
        return groups
    }

    /// Registry subcategories of a category, in first-seen order, each with its item count.
    private func node(for category: String) -> Category {
        var order: [String] = []
        var counts: [String: Int] = [:]
        for setting in settings where setting.category == category {
            guard let subcategory = setting.subcategory else { continue }
            if counts[subcategory] == nil {
                order.append(subcategory)
            }
            counts[subcategory, default: 0] += 1
        }
        let subcategories = order.map { Subcategory(name: $0, count: counts[$0] ?? 0) }
        return Category(name: category, subcategories: subcategories)
    }

    var filteredSettings: [DefaultSetting] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let scoped: [DefaultSetting]
        if let selectedCategory {
            scoped = settings.filter { $0.category == selectedCategory }
        } else {
            scoped = settings
        }
        if query.isEmpty {
            return scoped
        }
        return scoped.filter { setting in
            setting.title.localizedCaseInsensitiveContains(query)
                || setting.description.localizedCaseInsensitiveContains(query)
                || setting.key.localizedCaseInsensitiveContains(query)
                || setting.category.localizedCaseInsensitiveContains(query)
                || setting.domain.localizedCaseInsensitiveContains(query)
                || setting.id.localizedCaseInsensitiveContains(query)
        }
    }

    func canRevert(_ setting: DefaultSetting) -> Bool {
        appliedIds.contains(setting.id)
    }

    var hasPending: Bool { !pendingValues.isEmpty }

    var canRevertAll: Bool { !appliedIds.isEmpty }

    var isResetDisabled: Bool { pendingValues.isEmpty && appliedIds.isEmpty }

    /// Display value: staged pending edit wins over last applied state.
    func stagedString(_ setting: DefaultSetting) -> String {
        pendingValues[setting.id]
            ?? currentValues[setting.id]
            ?? fallbackString(for: setting)
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
        // File paths are staged as text; existence is not checked here.
        // String values keep edge spaces (e.g. " EEE d MMM HH:mm:ss ").
        let length = setting.type == .string
            ? stringValue.count
            : stringValue.trimmingCharacters(in: .whitespacesAndNewlines).count
        guard length <= 512 else {
            errorMessage = "Value for \(setting.id) exceeds 512 characters"
            return
        }
        let staged = canonicalStaged(setting, stringValue)
        guard value(for: setting, stringValue: staged) != nil else {
            errorMessage = "Could not parse value for \(setting.id)"
            return
        }
        if staged == currentValues[setting.id] {
            pendingValues.removeValue(forKey: setting.id)
        } else {
            pendingValues[setting.id] = staged
        }
    }

    /// Canonical staged form: trim whitespace, fold whole integers ("20.0" -> "20").
    /// String values keep edge spaces verbatim, and a leading `~/` as macOS stores it.
    private func canonicalStaged(_ setting: DefaultSetting, _ stringValue: String) -> String {
        if setting.type == .string {
            return stringValue
        }
        let trimmed = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if setting.type == .integer,
           let number = Double(trimmed),
           number == number.rounded(),
           number.isFinite,
           let intValue = Int(exactly: number)
        {
            return String(intValue)
        }
        return trimmed
    }

    func discardPending() {
        pendingValues = [:]
    }

    /// Writes all staged edits, clears pending, keeps failures staged.
    /// Spawns run in parallel batches of 8 and published state lands once per batch,
    /// so an N-id apply costs a small constant number of view invalidations, not 2N.
    @discardableResult
    func applyPending() async -> Bool {
        let staged = pendingValues
        guard !staged.isEmpty else { return true }
        guard !isApplying else { return false }
        isApplying = true
        defer { isApplying = false }
        let byId = Dictionary(uniqueKeysWithValues: settings.map { ($0.id, $0) })
        var failed: [String: String] = [:]
        var lastError: String?
        // Parse and eligibility cost no spawn, so they run here and keep an
        // unwritable id out of the batch entirely.
        var work: [(id: String, setting: DefaultSetting, staged: String, value: SettingValue)] = []
        for (id, stringValue) in staged {
            guard let setting = byId[id] else { continue }
            guard let parsed = value(for: setting, stringValue: stringValue) else {
                failed[id] = stringValue
                lastError = "Could not parse value for \(id)"
                continue
            }
            guard capturedIds.contains(setting.id) else {
                failed[id] = stringValue
                if lastError == nil { lastError = "No original captured for \(id); nothing was written" }
                continue
            }
            work.append((id, setting, stringValue, parsed))
        }
        var nextCurrent = currentValues
        var nextOn = isOn
        for offset in stride(from: 0, to: work.count, by: 8) {
            let chunk = Array(work[offset..<min(offset + 8, work.count)])
            await withTaskGroup(of: (Int, SettingValue?, String?).self) { group in
                for (index, item) in chunk.enumerated() {
                    group.addTask {
                        do {
                            try await DefaultsEngine.write(item.value, for: item.setting)
                            return (index, item.value, nil)
                        } catch {
                            return (index, nil, error.localizedDescription)
                        }
                    }
                }
                for await (index, written, failure) in group {
                    let item = chunk[index]
                    guard let written else {
                        failed[item.id] = item.staged
                        lastError = failure
                        continue
                    }
                    nextCurrent[item.id] = canonicalString(written)
                    nextOn[item.id] = matchesOn(current: item.staged, onValue: item.setting.onValue)
                    appliedIds.insert(item.id)
                }
            }
            currentValues = nextCurrent
            isOn = nextOn
        }
        pendingValues = failed
        errorMessage = lastError
        return failed.isEmpty
    }

    /// Discards pending edits, restores originals for applied tweaks.
    /// Same batching as `applyPending`: parallel spawns, one publish per batch.
    @discardableResult
    func resetAll() async -> Bool {
        guard !isApplying else { return false }
        isApplying = true
        defer { isApplying = false }
        pendingValues = [:]
        let byId = Dictionary(uniqueKeysWithValues: settings.map { ($0.id, $0) })
        var ok = true
        var firstError: String?
        var work: [(setting: DefaultSetting, original: SettingValue?)] = []
        for id in Array(appliedIds) {
            guard let setting = byId[id] else { continue }
            guard capturedIds.contains(setting.id) else {
                ok = false
                if firstError == nil { firstError = "No original value captured for \(id); nothing was changed." }
                continue
            }
            work.append((setting, originalValues[setting.id]))
        }
        var nextCurrent = currentValues
        var nextOn = isOn
        var nextPending = pendingValues
        for offset in stride(from: 0, to: work.count, by: 8) {
            let chunk = Array(work[offset..<min(offset + 8, work.count)])
            await withTaskGroup(of: (Int, String?).self) { group in
                for (index, item) in chunk.enumerated() {
                    group.addTask {
                        do {
                            try await Self.restore(item.original, for: item.setting)
                            return (index, nil)
                        } catch {
                            return (index, error.localizedDescription)
                        }
                    }
                }
                for await (index, failure) in group {
                    guard failure == nil else {
                        ok = false
                        if firstError == nil { firstError = failure }
                        continue
                    }
                    let item = chunk[index]
                    recordRevert(item.setting, original: item.original,
                                 current: &nextCurrent, on: &nextOn, pending: &nextPending)
                }
            }
            currentValues = nextCurrent
            isOn = nextOn
            pendingValues = nextPending
        }
        errorMessage = firstError
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
        var failureCount = 0
        var firstError: String?
        let all = settings
        let byId = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        // One `defaults export <domain>` spawn covers every entry in that domain.
        // `kCFPreferencesAnyApplication` is a CFPreferences pseudo-domain with no domain
        // of its own to read, so its entries stay on the per-key path.
        let pseudoDomain = "kCFPreferencesAnyApplication"
        let units: [(entries: [DefaultSetting], bulk: Bool)] =
            Set(all.map(\.domain)).subtracting([pseudoDomain]).map { domain in
                (entries: all.filter { $0.domain == domain }, bulk: true)
            } + all.filter { $0.domain == pseudoDomain }.map { (entries: [$0], bulk: false) }
        for offset in stride(from: 0, to: units.count, by: 8) {
            let chunk = Array(units[offset..<min(offset + 8, units.count)])
            await withTaskGroup(of: [(String, String?, String?)].self) { group in
                for unit in chunk {
                    group.addTask {
                        if unit.bulk, let values = try? await DefaultsEngine.readDomain(unit.entries[0].domain) {
                            return unit.entries.map { ($0.id, values[$0.key], nil) }
                        }
                        // A domain whose bulk output will not parse falls back to per-key
                        // reads, so a parse failure never becomes a user-visible error.
                        return await self.readPerKey(unit.entries)
                    }
                }
                for await results in group {
                    for (id, current, readError) in results {
                        if let readError {
                            failureCount += 1
                            if firstError == nil { firstError = readError }
                        }
                        guard let setting = byId[id] else { continue }
                        if let current {
                            newIsOn[id] = self.matchesOn(current: current, onValue: setting.onValue)
                            newCurrent[id] = current
                            self.captureOriginal(setting, current: current)
                        } else if readError == nil {
                            let fallback = self.fallbackString(for: setting)
                            newIsOn[id] = self.matchesOn(current: fallback, onValue: setting.onValue)
                            newCurrent[id] = fallback
                            self.captureOriginal(setting, current: nil)
                        } else {
                            // Transient read error: keep prior state, leave absent if never set.
                            if let prior = self.isOn[id] { newIsOn[id] = prior }
                            if let prior = self.currentValues[id] { newCurrent[id] = prior }
                        }
                    }
                }
            }
        }
        isOn = newIsOn
        currentValues = newCurrent
        // Keep staged edits unless disk now matches them (then resolved).
        pendingValues = pendingValues.filter { $0.value != newCurrent[$0.key] }
        if let firstError {
            errorMessage = "\(failureCount) of \(all.count) reads failed: \(firstError)"
        } else {
            errorMessage = nil
        }
    }

    /// One spawn per entry. Used for the pseudo-domain and as the bulk path's fallback.
    private func readPerKey(_ entries: [DefaultSetting]) async -> [(String, String?, String?)] {
        var results: [(String, String?, String?)] = []
        for setting in entries {
            do {
                results.append((setting.id, try await DefaultsEngine.read(domain: setting.domain, key: setting.key), nil))
            } catch {
                results.append((setting.id, nil, error.localizedDescription))
            }
        }
        return results
    }

    /// Canonical form for display, matching what `stage` puts in `pendingValues`.
    func displayString(_ value: SettingValue) -> String {
        canonicalString(value)
    }

    func value(for setting: DefaultSetting, stringValue: String) -> SettingValue? {
        switch setting.type {
        case .boolean:
            return boolean(stringValue).map(SettingValue.boolean)
        case .integer:
            guard let number = Int(stringValue) else { return nil }
            return .integer(number)
        case .string:
            return .string(stringValue)
        case .float:
            guard let number = Double(stringValue), number.isFinite else { return nil }
            return .float(number)
        }
    }

    /// `defaults read` prints a boolean as 1/0 in some domains and as true/false in
    /// others — `com.apple.finder CreateDesktop` prints `true`, `com.apple.dock
    /// autohide` prints `1` — so both spellings parse, whichever path read the value.
    func boolean(_ text: String) -> Bool? {
        switch text {
        case "1", "true": return true
        case "0", "false": return false
        default: return nil
        }
    }

    /// Restores the value read at load, parsed through the declared type.
    /// Deletes the key when it did not exist at load, restoring the system default.
    /// Shares the apply/reset guard so a row revert cannot interleave with a bulk run.
    @discardableResult
    func revert(_ setting: DefaultSetting) async -> Bool {
        guard !isApplying else { return false }
        isApplying = true
        defer { isApplying = false }
        guard capturedIds.contains(setting.id) else {
            errorMessage = "No original value captured for \(setting.id); nothing was changed."
            return false
        }
        let original = originalValues[setting.id]
        do {
            try await Self.restore(original, for: setting)
            var current = currentValues
            var on = isOn
            var pending = pendingValues
            recordRevert(setting, original: original, current: &current, on: &on, pending: &pending)
            currentValues = current
            isOn = on
            pendingValues = pending
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// The disk half of a revert: rewrite the captured value, or delete the key when it
    /// was absent at load. `nonisolated` so bulk batches spawn these off the main actor.
    private nonisolated static func restore(_ original: SettingValue?, for setting: DefaultSetting) async throws {
        if let original {
            try await DefaultsEngine.write(original, for: setting)
        } else {
            try await DefaultsEngine.delete(domain: setting.domain, key: setting.key)
        }
    }

    /// Restored-id bookkeeping, applied to the caller's batch dictionary so `@Published`
    /// fires once per batch instead of once per id.
    private func recordRevert(
        _ setting: DefaultSetting,
        original: SettingValue?,
        current: inout [String: String],
        on: inout [String: Bool],
        pending: inout [String: String]
    ) {
        let value = original.map { canonicalString($0) } ?? fallbackString(for: setting)
        current[setting.id] = value
        on[setting.id] = matchesOn(current: value, onValue: setting.onValue)
        capturedIds.remove(setting.id)
        appliedIds.remove(setting.id)
        originalValues.removeValue(forKey: setting.id)
        pending.removeValue(forKey: setting.id)
    }

    /// Records the pre-session value from the initial read, once per id. A value that
    /// does not parse as the declared type is left uncaptured, so `canRevert` stays false
    /// instead of offering a lossy restore.
    private func captureOriginal(_ setting: DefaultSetting, current: String?) {
        guard !capturedIds.contains(setting.id) else { return }
        if let current {
            // Any text parses as a String, so a dictionary or array read back as a plist
            // container must be rejected explicitly or revert would write it as a string.
            guard !isPlistContainer(current),
                  let parsed = value(for: setting, stringValue: current) else { return }
            originalValues[setting.id] = parsed
        } else {
            originalValues.removeValue(forKey: setting.id)
        }
        capturedIds.insert(setting.id)
    }

    private func isPlistContainer(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("{") || trimmed.hasPrefix("(")
    }

    /// Shown for a key with nothing on disk: the entry's `defaultValue`, else `offValue`.
    private func fallbackString(for setting: DefaultSetting) -> String {
        canonicalString(setting.defaultValue ?? setting.offValue)
    }

    /// Numeric-aware comparison: `defaults read` prints 0.0 as "0", and a boolean as
    /// either "1" or "true" depending on the domain.
    func matchesOn(current: String, onValue: SettingValue) -> Bool {
        switch onValue {
        case .boolean(let enabled):
            boolean(current) == enabled
        case .integer(let number):
            Int(current) == number
        case .float(let number):
            Double(current) == number
        case .string(let text):
            current == text
        }
    }

    /// Canonical form the app itself stages: booleans as 1/0, whole floats
    /// without the fraction (0.0 becomes "0").
    private func canonicalString(_ value: SettingValue) -> String {
        switch value {
        case .boolean(let enabled):
            enabled ? "1" : "0"
        case .integer(let number):
            String(number)
        case .string(let text):
            text
        case .float(let number):
            if number.isFinite, number == number.rounded(), let intValue = Int(exactly: number) {
                String(intValue)
            } else {
                String(number)
            }
        }
    }

    func loadRegistry() throws -> [DefaultSetting] {
        for bundle in Self.registryBundles() {
            if let url = bundle.url(forResource: "tweaks", withExtension: "json") {
                let data = try Data(contentsOf: url)
                let decoded = try JSONDecoder().decode([DefaultSetting].self, from: data)
                try Self.validate(decoded)
                return decoded
            }
        }
        throw RegistryError.missingFile
    }

    /// The app ships the registry in `Contents/Resources/SwiftDefaults_SwiftDefaults.bundle`.
    /// `Bundle.module` fatalErrors when the toolchain looks for the bundle in the app root,
    /// so read the shipped bundle first and keep `Bundle.module` for SwiftPM builds only.
    private static func registryBundles() -> [Bundle] {
        let main = Bundle.main
        if let url = main.url(forResource: "SwiftDefaults_SwiftDefaults", withExtension: "bundle"),
           let bundle = Bundle(url: url) {
            return [bundle, main]
        }
        #if SWIFT_PACKAGE
        return [Bundle.module, main]
        #else
        return [main]
        #endif
    }

    static func validate(_ entries: [DefaultSetting]) throws {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-")
        var ids = Set<String>()
        var targets = Set<String>()
        for entry in entries {
            guard ids.insert(entry.id).inserted else {
                throw RegistryError.duplicate("id \(entry.id)")
            }
            let target = "\(entry.domain)\u{0}\(entry.key)"
            guard targets.insert(target).inserted else {
                throw RegistryError.duplicate("domain+key \(entry.domain) \(entry.key)")
            }
            for field in [entry.domain, entry.key] {
                guard !field.isEmpty,
                      !field.hasPrefix("-"),
                      field.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
                      field.rangeOfCharacter(from: allowed.inverted) == nil
                else {
                    throw RegistryError.invalidEntry("\(entry.id): domain/key \(entry.domain) \(entry.key)")
                }
            }
        }
        // A category is either fully split into subcategories or fully flat, so the
        // sidebar never shows one section at category level and another one deeper.
        for (category, group) in Dictionary(grouping: entries, by: \.category) {
            guard let unlabelled = group.first(where: { $0.subcategory == nil }) else { continue }
            guard group.contains(where: { $0.subcategory != nil }) else { continue }
            throw RegistryError.invalidEntry("\(category): \(unlabelled.id) has no subcategory, but others in the category do")
        }
    }
}
