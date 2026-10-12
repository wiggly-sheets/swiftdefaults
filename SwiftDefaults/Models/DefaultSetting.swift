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
    let options: [SettingValue]?

    private enum CodingKeys: String, CodingKey {
        case id, category, title, description, domain, key, type
        case onValue, offValue, defaultValue, requiresRelaunch, appToRestart, options
    }

    /// Decodes values by the declared type, so float 0.0 stays a float.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        category = try container.decode(String.self, forKey: .category)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decode(String.self, forKey: .description)
        domain = try container.decode(String.self, forKey: .domain)
        key = try container.decode(String.self, forKey: .key)
        type = try container.decode(SettingType.self, forKey: .type)
        onValue = try Self.decodeValue(container, key: .onValue, as: type)
        offValue = try Self.decodeValue(container, key: .offValue, as: type)
        defaultValue = try Self.decodeOptionalValue(container, key: .defaultValue, as: type)
        requiresRelaunch = try container.decodeIfPresent(Bool.self, forKey: .requiresRelaunch)
        appToRestart = try container.decodeIfPresent(String.self, forKey: .appToRestart)
        if container.contains(.options) {
            var nested = try container.nestedUnkeyedContainer(forKey: .options)
            var values: [SettingValue] = []
            while !nested.isAtEnd {
                values.append(try Self.decodeUnkeyedValue(&nested, as: type))
            }
            options = values
        } else {
            options = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(category, forKey: .category)
        try container.encode(title, forKey: .title)
        try container.encode(description, forKey: .description)
        try container.encode(domain, forKey: .domain)
        try container.encode(key, forKey: .key)
        try container.encode(type, forKey: .type)
        try Self.encodeValue(onValue, to: &container, key: .onValue)
        try Self.encodeValue(offValue, to: &container, key: .offValue)
        if let defaultValue {
            try Self.encodeValue(defaultValue, to: &container, key: .defaultValue)
        }
        try container.encodeIfPresent(requiresRelaunch, forKey: .requiresRelaunch)
        try container.encodeIfPresent(appToRestart, forKey: .appToRestart)
        if let options {
            var nested = container.nestedUnkeyedContainer(forKey: .options)
            for value in options {
                switch (type, value) {
                case (.boolean, .boolean(let enabled)):
                    try nested.encode(enabled)
                case (.integer, .integer(let number)):
                    try nested.encode(number)
                case (.float, .float(let number)):
                    try nested.encode(number)
                case (.string, .string(let text)):
                    try nested.encode(text)
                default:
                    throw EncodingError.invalidValue(value, .init(codingPath: [], debugDescription: "Option type mismatch for \(id)"))
                }
            }
        }
    }

    private static func decodeValue(
        _ container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys,
        as type: SettingType
    ) throws -> SettingValue {
        switch type {
        case .boolean:
            return .boolean(try container.decode(Bool.self, forKey: key))
        case .integer:
            return .integer(try container.decode(Int.self, forKey: key))
        case .float:
            // Double decode also accepts whole JSON numbers (10 decodes as 10.0).
            return .float(try container.decode(Double.self, forKey: key))
        case .string:
            return .string(try container.decode(String.self, forKey: key))
        }
    }

    private static func decodeOptionalValue(
        _ container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys,
        as type: SettingType
    ) throws -> SettingValue? {
        guard container.contains(key) else { return nil }
        return try decodeValue(container, key: key, as: type)
    }

    private static func decodeUnkeyedValue(
        _ container: inout UnkeyedDecodingContainer,
        as type: SettingType
    ) throws -> SettingValue {
        switch type {
        case .boolean:
            return .boolean(try container.decode(Bool.self))
        case .integer:
            return .integer(try container.decode(Int.self))
        case .float:
            return .float(try container.decode(Double.self))
        case .string:
            return .string(try container.decode(String.self))
        }
    }

    private static func encodeValue(
        _ value: SettingValue,
        to container: inout KeyedEncodingContainer<CodingKeys>,
        key: CodingKeys
    ) throws {
        switch value {
        case .boolean(let enabled):
            try container.encode(enabled, forKey: key)
        case .integer(let number):
            try container.encode(number, forKey: key)
        case .string(let text):
            try container.encode(text, forKey: key)
        case .float(let number):
            try container.encode(number, forKey: key)
        }
    }
}
