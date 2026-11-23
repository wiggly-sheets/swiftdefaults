import Foundation

/// One transferable file: the values a Mac has set, so another Mac running the app
/// can take them over. Values are stored as canonical text in the form the app
/// stages, so a file stays readable and the receiving Mac re-parses it against its
/// own registry instead of trusting a foreign type.
struct SettingsProfile: Codable {
    /// Bumped when the file shape changes. A newer file is refused, never half-read.
    let format: Int
    let appVersion: String
    let macOSVersion: String
    let values: [Entry]

    struct Entry: Codable {
        let domain: String
        let key: String
        let type: SettingType
        let value: String
    }

    static let currentFormat = 1

    /// Builds a profile from the settings the caller selected, in a stable order.
    static func make(
        settings: [DefaultSetting],
        texts: [String: String],
        include ids: Set<String>,
        appVersion: String,
        macOSVersion: String
    ) -> SettingsProfile {
        let entries = settings
            .filter { ids.contains($0.id) }
            .compactMap { setting in
                texts[setting.id].map {
                    Entry(domain: setting.domain, key: setting.key, type: setting.type, value: $0)
                }
            }
            .sorted { ($0.domain, $0.key) < ($1.domain, $1.key) }
        return SettingsProfile(
            format: currentFormat,
            appVersion: appVersion,
            macOSVersion: macOSVersion,
            values: entries
        )
    }
}

/// What one import would stage, and why the rest was left out.
struct ProfileImport {
    /// Registry id to canonical staged text.
    var values: [String: String] = [:]
    /// One line per entry or entry group that was refused, for the summary.
    var skipped: [String] = []
    var warnings: [String] = []
}

/// The outcome the settings window reports after an import.
struct ProfileImportResult: Sendable {
    let staged: Int
    let unchanged: Int
    let skipped: [String]
    let warnings: [String]

    var summary: String {
        var lines = [
            "\(staged) value\(staged == 1 ? "" : "s") staged. Press Apply to write them.",
            "\(unchanged) value\(unchanged == 1 ? "" : "s") already matched this Mac.",
        ]
        if !warnings.isEmpty {
            lines.append("")
            lines.append(contentsOf: warnings)
        }
        if !skipped.isEmpty {
            lines.append("")
            lines.append("Not imported:")
            lines.append(contentsOf: skipped.prefix(10))
            if skipped.count > 10 {
                lines.append("…and \(skipped.count - 10) more.")
            }
        }
        return lines.joined(separator: "\n")
    }
}

enum ProfileError: Error, LocalizedError {
    case busy
    case empty
    case invalidFile
    case newerFormat(Int)

    var errorDescription: String? {
        switch self {
        case .busy:
            "Wait for the current write to finish."
        case .empty:
            "This Mac has no changed values to export yet."
        case .invalidFile:
            "This file is not a SwiftDefaults profile."
        case .newerFormat(let format):
            "The file uses format \(format), which this version cannot read. Update SwiftDefaults and try again."
        }
    }
}

extension SettingsProfile {
    /// Resolves a profile against this app's registry. Matching is by domain and key,
    /// so ids may change between versions. Anything the registry does not have, cannot
    /// parse, or declares as a different type is skipped and reported.
    static func plan(_ profile: SettingsProfile, settings: [DefaultSetting]) -> ProfileImport {
        var result = ProfileImport()
        let byTarget = Dictionary(
            uniqueKeysWithValues: settings.map { ("\($0.domain)\u{0}\($0.key)", $0) }
        )
        var seen = Set<String>()
        for entry in profile.values {
            let target = "\(entry.domain)\u{0}\(entry.key)"
            guard let setting = byTarget[target] else {
                result.skipped.append("\(entry.domain) \(entry.key): not in this version")
                continue
            }
            guard seen.insert(setting.id).inserted else {
                result.skipped.append("\(setting.id): appears more than once in the file")
                continue
            }
            guard entry.type == setting.type else {
                result.warnings.append(
                    "\(setting.id): type changed since the file was written, so its value was left out"
                )
                continue
            }
            guard entry.value.count <= 512 else {
                result.skipped.append("\(setting.id): value is too long")
                continue
            }
            guard let parsed = SettingValue.parse(entry.value, as: setting.type) else {
                result.skipped.append("\(setting.id): value does not match its type")
                continue
            }
            result.values[setting.id] = parsed.canonicalText
        }
        return result
    }

    /// One warning when the file came from another macOS major version. Keys can move
    /// between releases, so the caller still imports what the registry knows and says
    /// so plainly instead of guessing.
    static func versionNote(profile: SettingsProfile, currentMacOSVersion: String) -> String? {
        let exported = profile.macOSVersion.split(separator: ".").first.map(String.init)
            ?? profile.macOSVersion
        let current = currentMacOSVersion.split(separator: ".").first.map(String.init)
            ?? currentMacOSVersion
        guard exported != current else { return nil }
        return "Exported on macOS \(exported); this Mac runs macOS \(current). Some keys behave differently between releases, so check the values you rely on."
    }
}
