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

    /// A picker built from `options` must be able to show the setting's own on and off
    /// state. `loadRegistry` already rejects duplicate ids and targets, so that needs no
    /// separate test here.
    @MainActor
    func testOptionsContainOnAndOffValues() throws {
        for entry in try SettingsViewModel().loadRegistry() {
            guard let options = entry.options else { continue }
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
    func testValidateRejectsKeyLeadingHyphen() throws {
        let entries = try makeSettings("[" + entryJSON(id: "a", key: "-autohide") + "]")
        XCTAssertThrowsError(try SettingsViewModel.validate(entries)) { error in
            XCTAssertTrue("\(error)".contains("domain/key"), "\(error)")
        }
    }
}