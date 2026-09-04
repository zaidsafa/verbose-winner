import Foundation

/// Bounded protocol JSON, not the personal backup decoder. Decoded duplicate keys
/// and noncanonical/unsafe numbers reject before Foundation can normalize them.
enum TeamStrictJSON {
    static func object(_ data: Data, maximumBytes: Int = 32 * 1024) throws -> [String: Any] {
        guard data.count <= maximumBytes else { throw TeamAuthHTTPError.responseTooLarge }
        guard !data.starts(with: [0xef, 0xbb, 0xbf]), String(data: data, encoding: .utf8) != nil else {
            throw TeamAuthHTTPError.invalidResponse
        }
        var parser = Parser(bytes: Array(data))
        let value = try parser.value(depth: 0)
        parser.space()
        guard parser.index == parser.bytes.count, let object = value as? [String: Any] else {
            throw TeamAuthHTTPError.invalidResponse
        }
        return object
    }
    private struct Parser {
        let bytes: [UInt8]
        var index = 0
        var nodes = 0
        mutating func space() {
            while index < bytes.count, [9, 10, 13, 32].contains(bytes[index]) { index += 1 }
        }
        mutating func value(depth: Int) throws -> Any {
            nodes += 1; space()
            guard nodes <= 2048, index < bytes.count else { throw TeamAuthHTTPError.invalidResponse }
            switch bytes[index] {
            case 123: return try object(depth: depth + 1)
            case 91: return try array(depth: depth + 1)
            case 34: return try string()
            case 116: try literal(Array("true".utf8)); return true
            case 102: try literal(Array("false".utf8)); return false
            case 110: try literal(Array("null".utf8)); return NSNull()
            default: return try integer()
            }
        }
        mutating func object(depth: Int) throws -> [String: Any] {
            guard depth <= 4 else { throw TeamAuthHTTPError.invalidResponse }
            index += 1; space()
            var result = [String: Any]()
            if take(125) { return result }
            while true {
                space(); let key = try string()
                guard result[key] == nil else { throw TeamAuthHTTPError.invalidResponse }
                space(); guard take(58) else { throw TeamAuthHTTPError.invalidResponse }
                result[key] = try value(depth: depth)
                space(); if take(125) { return result }
                guard take(44) else { throw TeamAuthHTTPError.invalidResponse }
            }
        }
        mutating func array(depth: Int) throws -> [Any] {
            guard depth <= 4 else { throw TeamAuthHTTPError.invalidResponse }
            index += 1; space()
            var result = [Any]()
            if take(93) { return result }
            while true {
                result.append(try value(depth: depth))
                space(); if take(93) { return result }
                guard take(44) else { throw TeamAuthHTTPError.invalidResponse }
            }
        }
        mutating func string() throws -> String {
            let start = index
            guard take(34) else { throw TeamAuthHTTPError.invalidResponse }
            while index < bytes.count {
                let byte = bytes[index]; index += 1
                if byte == 34 {
                    let data = Data(bytes[start..<index])
                    guard let text = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? String else {
                        throw TeamAuthHTTPError.invalidResponse
                    }
                    return text
                }
                guard byte >= 32 else { throw TeamAuthHTTPError.invalidResponse }
                if byte == 92 {
                    guard index < bytes.count else { throw TeamAuthHTTPError.invalidResponse }
                    index += 1 // Foundation validates this escape/surrogate sequence.
                }
            }
            throw TeamAuthHTTPError.invalidResponse
        }
        mutating func integer() throws -> NSNumber {
            let start = index
            _ = take(45)
            guard index < bytes.count else { throw TeamAuthHTTPError.invalidResponse }
            if !take(48) {
                guard (49...57).contains(bytes[index]) else { throw TeamAuthHTTPError.invalidResponse }
                repeat { index += 1 } while index < bytes.count && (48...57).contains(bytes[index])
            }
            let raw = String(decoding: bytes[start..<index], as: UTF8.self)
            guard let value = Int64(raw), String(value) == raw,
                  (-TeamAuthWire.maximumSafeTime...TeamAuthWire.maximumSafeTime).contains(value) else {
                throw TeamAuthHTTPError.invalidResponse
            }
            return NSNumber(value: value)
        }
        mutating func literal(_ expected: [UInt8]) throws {
            guard index + expected.count <= bytes.count,
                  Array(bytes[index..<index + expected.count]) == expected else { throw TeamAuthHTTPError.invalidResponse }
            index += expected.count
        }
        mutating func take(_ byte: UInt8) -> Bool {
            guard index < bytes.count, bytes[index] == byte else { return false }
            index += 1; return true
        }
    }
}
