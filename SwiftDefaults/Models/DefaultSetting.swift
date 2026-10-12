import Foundation

/// Value types supported by the `defaults` system.
enum SettingType: String, Codable, Sendable {
    case boolean
    case integer
    case string
    case float
}

/// Untagged value matching the JSON number, string, or bool at the key.
enum SettingValue: Codable, Equatable, Sendable {
    case boolean(Bool)
    case integer(Int)
    case string(String)
    case float(Double)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) {
            self = .boolean(value)
        } else if let value = try? container.decode(Int.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .float(value)
        } else {
            self = .string(try container.decode(String.self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .boolean(let value):
            try container.encode(value)
        case .integer(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .float(let value):
            try container.encode(value)
        }
    }
}

/// One toggleable macOS default from the registry.
struct DefaultSetting: Codable, Identifiable, Sendable {
    let id: String
    let category: String
    let title: String
    let description: String
    let domain: String
    let key: String
    let type: SettingType
    let onValue: SettingValue
    let offValue: SettingValue
    let defaultValue: SettingValue?
    let requiresRelaunch: Bool?
    let appToRestart: String?
}
