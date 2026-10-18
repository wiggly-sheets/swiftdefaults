import Foundation
import XCTest
@testable import SwiftDefaults

/// Pure-function contracts. No test here spawns `defaults` or touches a real domain.
final class ParsingTests: XCTestCase {

    // MARK: - Boolean spelling

    /// Both spellings are real `defaults read` output: `com.apple.dock autohide`
    /// prints `1`, `com.apple.finder CreateDesktop` prints `true`.
    @MainActor
    func testBooleanParserAcceptsBothSpellings() {
        let viewModel = SettingsViewModel()
        XCTAssertEqual(viewModel.boolean("1"), true)
        XCTAssertEqual(viewModel.boolean("true"), true)
        XCTAssertEqual(viewModel.boolean("0"), false)
        XCTAssertEqual(viewModel.boolean("false"), false)
    }

    @MainActor
    func testBooleanParserRejectsGarbage() {
        let viewModel = SettingsViewModel()
        for text in ["", " ", "yes", "no", "2", "-1", "True", "TRUE", " true", "true ", "0.0", "null"] {
            XCTAssertNil(viewModel.boolean(text), "\(text.debugDescription) must not parse as a boolean")
        }
    }

    // MARK: - Absence detection

    /// These three strings are the actual messages `defaults` writes for a missing key
    /// or domain. The matcher used to key off wording that matched none of them, which
    /// broke 23 reads at once.
    func testAbsentDetectionMatchesRealDefaultsMessages() {
        let real = [
            "Error: Could not find key 'autohide' in domain 'com.apple.dock'.",
            "Error: Domain 'com.apple.nope' not found.",
            "Key autohide does not exist in domain com.apple.dock; leaving defaults unchanged",
        ]
        for message in real {
            XCTAssertTrue(DefaultsEngine.indicatesAbsent(message), message)
        }
    }

    /// shortcut: absence is recognised by message text, not by a distinct exit code,
    /// so any other nonzero output must not be mistaken for "absent".
    func testAbsentDetectionRejectsOtherFailures() {
        for message in [
            "defaults: unknown option: -bool",
            "",
            "Error: Could not write to domain com.apple.dock.",
            "Error: Permission denied",
        ] {
            XCTAssertFalse(DefaultsEngine.indicatesAbsent(message), message)
        }
    }

    // MARK: - Value parser

    @MainActor
    func testIntegerRejectsNonNumbers() throws {
        let viewModel = SettingsViewModel()
        let setting = try makeSetting(entryJSON(id: "int", type: "integer", on: "20", off: "0"))
        XCTAssertEqual(viewModel.value(for: setting, stringValue: "20"), .integer(20))
        XCTAssertNil(viewModel.value(for: setting, stringValue: "not-a-number"))
        XCTAssertNil(viewModel.value(for: setting, stringValue: "20.0"))
        XCTAssertNil(viewModel.value(for: setting, stringValue: ""))
    }

    @MainActor
    func testFloatRejectsNonNumbersAndNonFinite() throws {
        let viewModel = SettingsViewModel()
        let setting = try makeSetting(entryJSON(id: "float", type: "float", on: "1.5", off: "0"))
        XCTAssertEqual(viewModel.value(for: setting, stringValue: "1.5"), .float(1.5))
        XCTAssertNil(viewModel.value(for: setting, stringValue: "not-a-number"))
        XCTAssertNil(viewModel.value(for: setting, stringValue: "nan"))
        XCTAssertNil(viewModel.value(for: setting, stringValue: "inf"))
    }

    /// A boolean read back through the value parser keeps its meaning whichever
    /// spelling the domain printed.
    @MainActor
    func testBooleanRoundTripsThroughValueParser() throws {
        let viewModel = SettingsViewModel()
        let setting = try makeSetting(entryJSON(id: "bool"))
        XCTAssertEqual(viewModel.value(for: setting, stringValue: "true"), .boolean(true))
        XCTAssertEqual(viewModel.value(for: setting, stringValue: "1"), .boolean(true))
        XCTAssertEqual(viewModel.value(for: setting, stringValue: "false"), .boolean(false))
        XCTAssertEqual(viewModel.value(for: setting, stringValue: "0"), .boolean(false))
    }

    @MainActor
    func testStringKeepsEdgeSpacesVerbatim() throws {
        let viewModel = SettingsViewModel()
        let setting = try makeSetting(entryJSON(id: "str", type: "string", on: "\" EEE d MMM HH:mm:ss \"", off: "\"\""))
        let text = "  spaced out  "
        XCTAssertEqual(viewModel.value(for: setting, stringValue: text), .string(text))
        XCTAssertEqual(viewModel.displayString(.string(text)), text)
    }

    /// `type: float` with a whole JSON number must stay a float. Decoding it as an
    /// integer would make `Int64`-only paths and `matchesOn` disagree with the file.
    func testWholeJSONNumberOnFloatEntryStaysFloat() throws {
        let floatSetting = try makeSetting(entryJSON(id: "whole-float", type: "float", on: "10", off: "0"))
        XCTAssertEqual(floatSetting.onValue, .float(10))
        XCTAssertEqual(floatSetting.offValue, .float(0))
        let intSetting = try makeSetting(entryJSON(id: "whole-int", type: "integer", on: "10", off: "0"))
        XCTAssertEqual(intSetting.onValue, .integer(10))
        XCTAssertNotEqual(intSetting.onValue, floatSetting.onValue)
    }

    // MARK: - Absent-key fallback

    /// Shown for a key with nothing on disk: `defaultValue` when present, else `offValue`.
    @MainActor
    func testAbsentKeyPrefersDefaultValueThenOffValue() throws {
        let viewModel = SettingsViewModel()
        let withDefault = try makeSetting(
            entryJSON(id: "with-default", type: "integer", on: "2", off: "1", extra: ", \"defaultValue\": 7")
        )
        XCTAssertEqual(viewModel.stagedString(withDefault), "7")
        let withoutDefault = try makeSetting(entryJSON(id: "no-default", type: "boolean", on: "true", off: "false"))
        XCTAssertEqual(viewModel.stagedString(withoutDefault), "0")
    }

    // MARK: - Folder staging

    func testStagedFolderValuePrefersListedOptionLiteral() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        XCTAssertEqual(
            DefaultSetting.stagedFolderValue(options: ["~/Desktop", "/Volumes/Work"], chosenPath: "\(home)/Desktop"),
            "~/Desktop"
        )
        XCTAssertEqual(
            DefaultSetting.stagedFolderValue(options: ["~/Desktop"], chosenPath: "/Volumes/Other"),
            "/Volumes/Other"
        )
        XCTAssertEqual(
            DefaultSetting.stagedFolderValue(options: ["/Volumes/Work"], chosenPath: "/Volumes/Work"),
            "/Volumes/Work"
        )
    }

    // MARK: - Staging and comparison (in memory only, nothing is written)

    /// Staging a string keeps the spaces the user typed. Trimming here would silently
    /// rewrite values like `" EEE d MMM HH:mm:ss "`.
    @MainActor
    func testStringStagingKeepsEdgeSpacesVerbatim() throws {
        let viewModel = SettingsViewModel()
        let setting = try makeSetting(entryJSON(id: "str", type: "string", on: "\"\"", off: "\"\""))
        viewModel.stageOption(setting, stringValue: "  spaced out  ")
        XCTAssertEqual(viewModel.pendingValues["str"], "  spaced out  ")
        XCTAssertEqual(viewModel.stagedString(setting), "  spaced out  ")
    }

    /// A staged integer folds to its canonical form; a staged float is trimmed only.
    @MainActor
    func testNumericStagingIsCanonical() throws {
        let viewModel = SettingsViewModel()
        let int = try makeSetting(entryJSON(id: "int", type: "integer", on: "20", off: "0"))
        viewModel.stageOption(int, stringValue: " 20.0 ")
        XCTAssertEqual(viewModel.pendingValues["int"], "20")
        let float = try makeSetting(entryJSON(id: "float", type: "float", on: "1.5", off: "0"))
        viewModel.stageOption(float, stringValue: " 1.5 ")
        XCTAssertEqual(viewModel.pendingValues["float"], "1.5")
        XCTAssertNil(viewModel.errorMessage)
    }

    /// Unparseable input must not be staged at all.
    @MainActor
    func testUnparseableStagingIsRejected() throws {
        let viewModel = SettingsViewModel()
        let int = try makeSetting(entryJSON(id: "int", type: "integer", on: "20", off: "0"))
        viewModel.stageOption(int, stringValue: "not-a-number")
        XCTAssertNil(viewModel.pendingValues["int"])
        XCTAssertNotNil(viewModel.errorMessage)
    }

    @MainActor
    func testBooleanToggleStagesCanonicalSpelling() throws {
        let viewModel = SettingsViewModel()
        let setting = try makeSetting(entryJSON(id: "bool"))
        viewModel.stage(setting, on: true)
        XCTAssertEqual(viewModel.pendingValues["bool"], "1")
        XCTAssertTrue(viewModel.stagedIsOn(setting))
        viewModel.stage(setting, on: false)
        XCTAssertEqual(viewModel.pendingValues["bool"], "0")
        XCTAssertFalse(viewModel.stagedIsOn(setting))
    }

    /// `defaults read` prints 0.0 as "0" and a boolean as "1" or "true" depending on
    /// the domain, so every comparison has to speak both.
    @MainActor
    func testMatchesOnSpeaksBothNumericAndBooleanSpellings() {
        let viewModel = SettingsViewModel()
        XCTAssertTrue(viewModel.matchesOn(current: "1", onValue: .boolean(true)))
        XCTAssertTrue(viewModel.matchesOn(current: "true", onValue: .boolean(true)))
        XCTAssertFalse(viewModel.matchesOn(current: "1", onValue: .boolean(false)))
        XCTAssertFalse(viewModel.matchesOn(current: "false", onValue: .boolean(true)))
        XCTAssertTrue(viewModel.matchesOn(current: "10", onValue: .integer(10)))
        XCTAssertFalse(viewModel.matchesOn(current: "10.0", onValue: .integer(10)))
        XCTAssertTrue(viewModel.matchesOn(current: "10", onValue: .float(10)))
        XCTAssertTrue(viewModel.matchesOn(current: "10.0", onValue: .float(10)))
        XCTAssertTrue(viewModel.matchesOn(current: " text ", onValue: .string(" text ")))
    }

    // MARK: - Container rendering

    /// `captureOriginal` refuses to capture text starting with `{` or `(`, so a rendered
    /// container that lost its marker would be captured as a String and written back wrong.
    func testRenderedContainersAlwaysStartWithBraceOrParen() {
        let values: [Any] = [
            Data([0x00, 0x01, 0x02]),
            ["key": "value"] as [String: Any],
            ["key": Data([0x00])] as [String: Any],
            ["a", "b"] as [Any],
            [[1, 2]] as [Any],
            NSDate(),
            Date(),
        ]
        for value in values {
            let rendered = DefaultsEngine.rendered(value)
            XCTAssertTrue(
                rendered.hasPrefix("{") || rendered.hasPrefix("("),
                "\(type(of: value)) rendered as \(rendered)"
            )
        }
    }

    func testRenderedScalarsDoNotLookLikeContainers() {
        XCTAssertFalse(DefaultsEngine.rendered("plain").hasPrefix("{"))
        XCTAssertFalse(DefaultsEngine.rendered(42).hasPrefix("{"))
        XCTAssertFalse(DefaultsEngine.rendered(4.5).hasPrefix("("))
    }

    /// Whole floats print without the fraction in `defaults read`, and that is the form
    /// the app stages, so a round trip must not turn `0.0` into `0.5`-style noise.
    func testRenderedWholeFloatPrintsWithoutFraction() {
        XCTAssertEqual(DefaultsEngine.rendered(10.0), "10")
        XCTAssertEqual(DefaultsEngine.rendered(1.5), "1.5")
        XCTAssertEqual(DefaultsEngine.rendered(10), "10")
    }

    // MARK: - Numeric clamp

    /// `Int(_:)` traps on NaN, infinity and out-of-range doubles, and this runs while
    /// drawing the row. Nothing here may trap.
    @MainActor
    func testSafeIntClampsInsteadOfTrapping() throws {
        let row = SettingRowView(setting: try makeSetting(
            entryJSON(id: "stepper", type: "integer", on: "5", off: "0", extra: ", \"options\": [0, 5, 10]")
        ))
        // Integers that convert exactly are returned as they are, out of range included:
        // the display path must show what is on disk, not a clamped lie.
        XCTAssertEqual(row.safeInt(3), 3)
        XCTAssertEqual(row.safeInt(999), 999)
        XCTAssertEqual(row.safeInt(-5), -5)
        // Everything `Int(exactly:)` refuses is brought back into the control's range.
        XCTAssertEqual(row.safeInt(.nan), 0)
        XCTAssertEqual(row.safeInt(.infinity), 10)
        XCTAssertEqual(row.safeInt(-.infinity), 0)
        XCTAssertEqual(row.safeInt(Double(Int64.max)), 10)
        XCTAssertEqual(row.safeInt(9_223_372_036_854_775_808), 10)
        XCTAssertEqual(row.safeInt(1e300), 10)
    }

    /// Same clamp with no declared options, so the range is the built-in `0...512`.
    @MainActor
    func testSafeIntClampsToBuiltInRange() throws {
        let row = SettingRowView(setting: try makeSetting(entryJSON(id: "free-stepper", type: "integer", on: "20", off: "0")))
        XCTAssertEqual(row.safeInt(.nan), 0)
        XCTAssertEqual(row.safeInt(1e300), 512)
    }
}