import Foundation
import XCTest
@testable import SwiftDefaults

/// Profile file contracts: what a receiving Mac accepts, what it refuses, and why.
final class ProfileTests: XCTestCase {

    private func profile(_ entries: [SettingsProfile.Entry], format: Int = SettingsProfile.currentFormat) -> SettingsProfile {
        SettingsProfile(format: format, appVersion: "1.0", macOSVersion: "26.1.0", values: entries)
    }

    /// Matching is by domain and key, not by id, so an entry survives an id rename.
    /// Every canonical value in the file resolves back to the same typed value.
    func testProfileRoundTripResolvesByDomainAndKey() throws {
        let settings = try makeSettings("""
        [
          \(entryJSON(id: "dock-autohide", domain: "com.apple.dock", key: "autohide")),
          \(entryJSON(id: "clock-format", domain: "com.apple.menuextra.clock", key: "DateFormat", type: "string", on: "\" EEE d MMM HH:mm:ss \"", off: "\"\""))
        ]
        """)
        let texts = [
            "dock-autohide": "1",
            "clock-format": " EEE d MMM HH:mm:ss ",
        ]
        let file = SettingsProfile.make(
            settings: settings,
            texts: texts,
            include: Set(settings.map(\.id)),
            appVersion: "1.0",
            macOSVersion: "26.1.0"
        )
        let decoded = try JSONDecoder().decode(
            SettingsProfile.self,
            from: JSONEncoder().encode(file)
        )
        let plan = SettingsProfile.plan(decoded, settings: settings)
        XCTAssertEqual(plan.values, texts)
        XCTAssertTrue(plan.skipped.isEmpty)
        XCTAssertTrue(plan.warnings.isEmpty)
    }

    /// A file from another Mac may name keys this version lacks, repeat itself, hold text
    /// that is not the declared type, or declare a type that has since changed. The first
    /// occurrence wins and everything else is reported, never guessed.
    func testPlanSkipsUnknownDuplicateInvalidAndRetypedEntries() throws {
        let settings = try makeSettings("""
        [
          \(entryJSON(id: "dock-autohide", domain: "com.apple.dock", key: "autohide")),
          \(entryJSON(id: "dock-tilesize", domain: "com.apple.dock", key: "tilesize", type: "integer", on: "48", off: "64")),
          \(entryJSON(id: "finder-desktop", domain: "com.apple.finder", key: "CreateDesktop", on: "true", off: "false"))
        ]
        """)
        let file = profile([
            .init(domain: "com.apple.dock", key: "autohide", type: .boolean, value: "true"),
            .init(domain: "com.apple.dock", key: "autohide", type: .boolean, value: "false"),
            .init(domain: "com.apple.dock", key: "tilesize", type: .integer, value: "not-a-number"),
            .init(domain: "com.apple.dock", key: "tilesize", type: .string, value: "48"),
            .init(domain: "com.apple.finder", key: "CreateDesktop", type: .string, value: "true"),
            .init(domain: "com.apple.old", key: "gone", type: .boolean, value: "1"),
        ])
        let plan = SettingsProfile.plan(file, settings: settings)
        XCTAssertEqual(plan.values, ["dock-autohide": "1"])
        XCTAssertEqual(plan.skipped.count, 4)
        XCTAssertEqual(plan.warnings.count, 1)
        XCTAssertTrue(plan.skipped.contains { $0.contains("appears more than once") })
        XCTAssertTrue(plan.skipped.contains { $0.contains("does not match its type") })
        XCTAssertTrue(plan.skipped.contains { $0.contains("not in this version") })
        XCTAssertTrue(plan.warnings[0].contains("type changed"))
    }

    /// A major macOS change moves keys around, so it is surfaced even though the import
    /// still applies what the registry knows.
    func testVersionNoteFlagsDifferentMajorVersionOnly() {
        let file = profile([])
        XCTAssertNil(SettingsProfile.versionNote(profile: file, currentMacOSVersion: "26.2.0"))
        XCTAssertNotNil(SettingsProfile.versionNote(profile: file, currentMacOSVersion: "27.0.0"))
    }

    /// A newer file shape is refused whole; nothing from it is staged.
    @MainActor
    func testImportRefusesNewerFormatAndMalformedFiles() throws {
        let viewModel = SettingsViewModel()
        let newer = profile([], format: SettingsProfile.currentFormat + 1)
        let data = try JSONEncoder().encode(newer)
        XCTAssertThrowsError(try viewModel.importProfile(data)) { error in
            guard case ProfileError.newerFormat = error else {
                return XCTFail("expected newerFormat, got \(error)")
            }
        }
        XCTAssertThrowsError(try viewModel.importProfile(Data("not json".utf8))) { error in
            guard case ProfileError.invalidFile = error else {
                return XCTFail("expected invalidFile, got \(error)")
            }
        }
    }
}
