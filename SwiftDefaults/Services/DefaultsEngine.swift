import Foundation

/// Errors from the `defaults` CLI wrapper.
enum DefaultsError: Error, LocalizedError {
    case launchFailed(Error)
    case writeFailed(Int32, String)
    case typeMismatch(id: String)
    case unreadableDomain(String)

    var errorDescription: String? {
        switch self {
        case .launchFailed(let error):
            "Could not launch defaults: \(error.localizedDescription)"
        case .writeFailed(let status, let output):
            "defaults exited with status \(status): \(output)"
        case .typeMismatch(let id):
            "Value type does not match setting type for \(id)"
        case .unreadableDomain(let domain):
            "Could not read domain \(domain) as a whole"
        }
    }
}

/// Thin async wrapper over /usr/bin/defaults. No state, no force-unwrap.
enum DefaultsEngine {
    private static let executableURL = URL(fileURLWithPath: "/usr/bin/defaults")

    /// Raw `defaults read` output, or nil when the key does not exist.
    static func read(domain: String, key: String) async throws -> String? {
        let (status, output) = try await run(arguments: ["read", domain, key])
        if status == 0 {
            return output.trimmingCharacters(in: .newlines)
        }
        if indicatesAbsent(output) {
            return nil
        }
        throw DefaultsError.writeFailed(status, output)
    }

    /// Bulk `defaults export <domain> -`: every key the domain holds, in one spawn.
    /// Export, not `read`: `defaults read` prints old-style plist, where an NSData
    /// value prints as `{length = 684, bytes = 0x...}` and the whole output stops
    /// parsing. `export` emits the same data as XML plist, which parses cleanly.
    /// A key the domain does not have is simply absent from the result, which is the
    /// normal state for an unset setting, so a missing domain is not an error either.
    /// Throws `unreadableDomain` only when the output will not parse, so the caller can
    /// fall back to per-key reads instead of reporting failures.
    static func readDomain(_ domain: String) async throws -> [String: String] {
        let (status, output) = try await run(arguments: ["export", domain, "-"])
        if status != 0 {
            guard indicatesAbsent(output) else { throw DefaultsError.writeFailed(status, output) }
            return [:]
        }
        guard let data = output.data(using: .utf8),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dictionary = plist as? [String: Any]
        else { throw DefaultsError.unreadableDomain(domain) }
        return dictionary.reduce(into: [:]) { result, pair in
            result[pair.key] = rendered(pair.value)
        }
    }

    /// Renders a parsed plist value the way `defaults read <domain> <key>` prints it.
    /// Foundation cannot write openstep, so container text is hand-rolled: a caller's
    /// plist-container guard keys off the leading `{` or `(` and must never see `""`.
    private static func rendered(_ value: Any) -> String {
        switch value {
        case let text as String:
            return text
        case let number as NSNumber:
            guard CFNumberIsFloatType(number) else { return number.stringValue }
            // `defaults read` prints a whole float without the fraction, 100.0 as "100",
            // and that is the form `SettingsViewModel.canonicalString` stages.
            let double = number.doubleValue
            guard double.isFinite, double == double.rounded(), let whole = Int(exactly: double) else {
                return String(double)
            }
            return String(whole)
        case let data as Data:
            return "{ length = \(data.count) }"
        case let pairs as [String: Any]:
            let body = pairs.keys.sorted().compactMap { key -> String? in
                pairs[key].map { "\(key) = \(rendered($0));" }
            }
            return "{ \(body.joined(separator: " ")) }"
        case let items as [Any]:
            return "( \(items.map(rendered).joined(separator: ", ")) )"
        default:
            // NSDate and anything else opaque: still a container marker, so the guard
            // refuses to capture it as a String rather than losing the value flat.
            return "{ \(value) }"
        }
    }

    static func write(_ value: SettingValue, for setting: DefaultSetting) async throws {
        var arguments = ["write", setting.domain, setting.key]
        switch (setting.type, value) {
        case (.boolean, .boolean(let enabled)):
            arguments += ["-bool", enabled ? "true" : "false"]
        case (.integer, .integer(let number)):
            arguments += ["-int", String(number)]
        case (.string, .string(let text)):
            arguments += ["-string", text]
        case (.float, .float(let number)):
            arguments += ["-float", String(number)]
        default:
            throw DefaultsError.typeMismatch(id: setting.id)
        }
        let (status, output) = try await run(arguments: arguments)
        guard status == 0 else {
            throw DefaultsError.writeFailed(status, output)
        }
    }

    /// Deletes the key, restoring the system default. Used for revert.
    static func delete(domain: String, key: String) async throws {
        let (status, output) = try await run(arguments: ["delete", domain, key])
        if status == 0 || indicatesAbsent(output) {
            return
        }
        throw DefaultsError.writeFailed(status, output)
    }

    /// True when a nonzero exit means "key or domain is not there", not a real failure.
    /// `run` merges stderr into `output`, so these arrive on the same string.
    ///
    /// shortcut: matching on English message text, because `defaults` exposes no distinct
    /// exit code for absence. Add a code check here if a future macOS localises these.
    private static func indicatesAbsent(_ output: String) -> Bool {
        // macOS 27: "Error: Could not find key 'k' in domain 'd'." (unset key in a real domain)
        //           "Error: Domain 'd' not found."                        (unknown domain)
        //           "Key k does not exist in domain d; leaving defaults unchanged" (older releases)
        output.contains("Could not find key")
            || output.contains("not found")
            || output.contains("does not exist")
    }

    private static func run(arguments: [String]) async throws -> (Int32, String) {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = executableURL
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            do {
                try process.run()
            } catch {
                throw DefaultsError.launchFailed(error)
            }
            // Drain before reaping: a child that outfills the pipe buffer blocks in write(),
            // so waitUntilExit() first would never return.
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
        }.value
    }
}
