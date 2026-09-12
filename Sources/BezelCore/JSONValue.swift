import Foundation

/// A JSON value this build does not have a field for.
///
/// It exists so a configuration file written by a *newer* build survives being
/// read and rewritten by an older one. Without it, decoding dropped every
/// unrecognised key and the next ordinary save — changing the language, picking
/// a Host — wrote the file back without them, silently downgrading a file that
/// still claimed the newer version number.
///
/// Deliberately just enough to hold what JSON can express, and nothing more:
/// this type never inspects the values it carries, it only keeps them intact.
public enum JSONValue: Equatable, Sendable {
    case null
    case bool(Bool)
    /// Kept apart from `double` so `"port": 3080` is written back as `3080`
    /// rather than `3080.0`.
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])
}

extension JSONValue: Codable {
    public init(from decoder: any Decoder) throws {
        if let container = try? decoder.container(keyedBy: JSONCodingKey.self) {
            var object: [String: JSONValue] = [:]
            for key in container.allKeys {
                object[key.stringValue] = try container.decode(JSONValue.self, forKey: key)
            }
            self = .object(object)
            return
        }
        if var container = try? decoder.unkeyedContainer() {
            var array: [JSONValue] = []
            while !container.isAtEnd {
                array.append(try container.decode(JSONValue.self))
            }
            self = .array(array)
            return
        }
        let single = try decoder.singleValueContainer()
        if single.decodeNil() {
            self = .null
        } else if let value = try? single.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? single.decode(Int.self) {
            self = .int(value)
        } else if let value = try? single.decode(Double.self) {
            self = .double(value)
        } else {
            self = .string(try single.decode(String.self))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        switch self {
        case .null:
            var single = encoder.singleValueContainer()
            try single.encodeNil()
        case .bool(let value):
            var single = encoder.singleValueContainer()
            try single.encode(value)
        case .int(let value):
            var single = encoder.singleValueContainer()
            try single.encode(value)
        case .double(let value):
            var single = encoder.singleValueContainer()
            try single.encode(value)
        case .string(let value):
            var single = encoder.singleValueContainer()
            try single.encode(value)
        case .array(let values):
            var container = encoder.unkeyedContainer()
            for value in values {
                try container.encode(value)
            }
        case .object(let values):
            var container = encoder.container(keyedBy: JSONCodingKey.self)
            for (key, value) in values {
                try container.encode(value, forKey: JSONCodingKey(key))
            }
        }
    }
}

/// A coding key made from whatever string the file happens to hold.
struct JSONCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }

    init(_ stringValue: String) {
        self.stringValue = stringValue
    }

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
    }
}
