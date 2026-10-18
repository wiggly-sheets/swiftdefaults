import Foundation
@testable import SwiftDefaults

/// Builds `DefaultSetting` values through the real `Codable` path, so a fixture can
/// never disagree with the shape the registry file actually has.
func makeSetting(_ json: String) throws -> DefaultSetting {
    try JSONDecoder().decode([DefaultSetting].self, from: Data("[\(json)]".utf8))[0]
}

func makeSettings(_ json: String) throws -> [DefaultSetting] {
    try JSONDecoder().decode([DefaultSetting].self, from: Data(json.utf8))
}

/// Registry entry with every field spelled out; callers override only what they test.
func entryJSON(
    id: String,
    category: String = "Probe",
    subcategory: String? = nil,
    domain: String = "com.apple.dock",
    key: String = "autohide",
    type: String = "boolean",
    on: String = "true",
    off: String = "false",
    extra: String = ""
) -> String {
    let sub = subcategory.map { "\"subcategory\": \"\($0)\"," } ?? ""
    return """
    {"id": "\(id)", "category": "\(category)", \(sub) "title": "\(id)", "description": "d",
     "domain": "\(domain)", "key": "\(key)", "type": "\(type)",
     "onValue": \(on), "offValue": \(off)\(extra)}
    """
}