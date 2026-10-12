import Foundation

/// Errors from the `defaults` CLI wrapper.
enum DefaultsError: Error, LocalizedError {
    case launchFailed(Error)
    case writeFailed(Int32, String)
    case typeMismatch(id: String)

    var errorDescription: String? {
        switch self {
        case .launchFailed(let error):
            "Could not launch defaults: \(error.localizedDescription)"
        case .writeFailed(let status, let output):
            "defaults exited with status \(status): \(output)"
        case .typeMismatch(let id):
            "Value type does not match setting type for \(id)"
        }
    }
}

/// Thin async wrapper over /usr/bin/defaults. No state, no force-unwrap.
enum DefaultsEngine {
    private static let executableURL = URL(fileURLWithPath: "/usr/bin/defaults")

    /// Raw `defaults read` output, or nil when the key does not exist.
    static func read(domain: String, key: String) async throws -> String? {
        let (status, output) = try await run(arguments: ["read", domain, key])
        guard status == 0 else { return nil }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
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
        guard status == 0 else {
            throw DefaultsError.writeFailed(status, output)
        }
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
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
        }.value
    }
}
