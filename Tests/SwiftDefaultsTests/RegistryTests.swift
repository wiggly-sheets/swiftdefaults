import Foundation
import XCTest
@testable import SwiftDefaults

/// The shipped registry, read through the same path the app uses at launch.
final class RegistryTests: XCTestCase {

    /// Also the `Bundle.module` check: this only passes if `tweaks.json` resolves from
    /// inside the test bundle. The count is not pinned here — it moves whenever a
    /// tweak is added — and the registry itself is still asserted non-empty.
    @MainActor
    func testRegistryLoadsFromBundleModule() throws {
        let entries = try SettingsViewModel().loadRegistry()
        XCTAssertFalse(entries.isEmpty)
    }

    @MainActor
    func testRegistryHasNoDuplicateIdsOrTargets() throws {
        let entries = try SettingsViewModel().loadRegistry()
        XCTAssertEqual(Set(entries.map(\.id)).count, entries.count, "duplicate id")
        let targets = entries.map { "\($0.domain)\u{0}\($0.key)" }
        XCTAssertEqual(Set(targets).count, targets.count, "duplicate domain+key")
    }

    /// Decoding is type-driven, so every value must arrive as the declared case.
    /// Integers and floats are distinguished: `10` on a float entry is `.float(10)`.
    @MainActor
    func testRegistryValuesMatchDeclaredTypes() throws {
        for entry in try SettingsViewModel().loadRegistry() {
            let values: [(String, SettingValue?)] = [
                ("onValue", entry.onValue), ("offValue", entry.offValue),
                ("defaultValue", entry.defaultValue),
            ]
            for (field, value) in values {
                guard let value else { continue }
                assertType(entry.type, value, "\(entry.id).\(field)")
            }
            for (index, option) in (entry.options ?? []).enumerated() {
                assertType(entry.type, option, "\(entry.id).options[\(index)]")
            }
        }
    }

    /// A picker built from `options` must be able to show the setting's own on and off
    /// state, or the row cannot represent the value it is about to write.
    @MainActor
    func testNonBooleanOptionsContainOnAndOffValues() throws {
        for entry in try SettingsViewModel().loadRegistry() where entry.type != .boolean {
            guard let options = entry.options else {
                XCTFail("\(entry.id) is \(entry.type.rawValue) with no options")
                continue
            }
            XCTAssertTrue(options.contains(entry.onValue), "\(entry.id) options miss onValue \(entry.onValue)")
            XCTAssertTrue(options.contains(entry.offValue), "\(entry.id) options miss offValue \(entry.offValue)")
        }
    }

    // MARK: - Rejected registries

    @MainActor
    func testValidateRejectsDuplicateID() throws {
        let entries = try makeSettings("[" + [entryJSON(id: "same"), entryJSON(id: "same")].joined(separator: ",") + "]")
        XCTAssertThrowsError(try SettingsViewModel.validate(entries)) { error in
            XCTAssertTrue("\(error)".contains("id same"), "\(error)")
        }
    }

    @MainActor
    func testValidateRejectsDuplicateDomainAndKey() throws {
        let entries = try makeSettings("[" + [
            entryJSON(id: "a", domain: "com.apple.dock", key: "autohide"),
            entryJSON(id: "b", domain: "com.apple.dock", key: "autohide"),
        ].joined(separator: ",") + "]")
        XCTAssertThrowsError(try SettingsViewModel.validate(entries)) { error in
            XCTAssertTrue("\(error)".contains("domain+key"), "\(error)")
        }
    }

    @MainActor
    func testValidateRejectsHalfSplitCategory() throws {
        let entries = try makeSettings("[" + [
            entryJSON(id: "a", category: "Dock", subcategory: "Behaviour"),
            entryJSON(id: "b", category: "Dock", key: "tilesize"),
        ].joined(separator: ",") + "]")
        XCTAssertThrowsError(try SettingsViewModel.validate(entries)) { error in
            XCTAssertTrue("\(error)".contains("subcategory"), "\(error)")
        }
    }

    @MainActor
    func testValidateAcceptsFullySplitAndFullyFlatCategories() throws {
        let split = try makeSettings("[" + [
            entryJSON(id: "a", category: "Dock", subcategory: "Behaviour"),
            entryJSON(id: "b", category: "Dock", subcategory: "Layout", key: "tilesize"),
        ].joined(separator: ",") + "]")
        XCTAssertNoThrow(try SettingsViewModel.validate(split))
        let flat = try makeSettings("[" + [
            entryJSON(id: "a", category: "Dock"),
            entryJSON(id: "b", category: "Dock", key: "tilesize"),
        ].joined(separator: ",") + "]")
        XCTAssertNoThrow(try SettingsViewModel.validate(flat))
    }

    @MainActor
    func testValidateRejectsOptionLeadingHyphen() throws {
        let entries = try makeSettings("[" + entryJSON(id: "a", key: "-autohide") + "]")
        XCTAssertThrowsError(try SettingsViewModel.validate(entries)) { error in
            XCTAssertTrue("\(error)".contains("domain/key"), "\(error)")
        }
    }

    // MARK: - Helpers

    private func assertType(
        _ declared: SettingType,
        _ value: SettingValue,
        _ label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        switch (declared, value) {
        case (.boolean, .boolean), (.integer, .integer), (.string, .string), (.float, .float):
            return
        default:
            XCTFail("\(label) is \(value) but the entry declares \(declared.rawValue)", file: file, line: line)
        }
    }
}