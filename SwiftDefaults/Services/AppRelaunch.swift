import Foundation

/// Relaunches apps whose settings the user just wrote. Only called from an explicit
/// click on the relaunch prompt; nothing here runs on its own.
enum AppRelaunch {
    private static let executableURL = URL(fileURLWithPath: "/usr/bin/killall")

    /// Asks the named apps to quit. Apps macOS owns, such as the Dock and
    /// SystemUIServer, relaunch themselves. Returns the names that could not be
    /// relaunched; an app that was not running counts as nothing to do.
    static func relaunch(_ apps: [String]) async -> [String] {
        var failures: [String] = []
        for app in apps {
            guard isSafeName(app) else {
                failures.append(app)
                continue
            }
            do {
                let status = try await run(app)
                if status != 0, status != 1 {
                    failures.append(app)
                }
            } catch {
                failures.append(app)
            }
        }
        return failures
    }

    /// Registry app names are trusted bundled data, but a name still has to look like
    /// an app name before it reaches `killall`, so a hand-edited registry cannot pass
    /// flags or paths.
    private static func isSafeName(_ name: String) -> Bool {
        !name.isEmpty && name.allSatisfy { $0.isLetter || $0.isNumber || $0 == " " || $0 == "." }
    }

    private static func run(_ app: String) async throws -> Int32 {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = executableURL
            process.arguments = [app]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            try process.run()
            _ = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return process.terminationStatus
        }.value
    }
}
