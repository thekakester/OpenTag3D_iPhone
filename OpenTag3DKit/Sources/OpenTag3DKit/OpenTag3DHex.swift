import Foundation

/// Internal hexadecimal conversion utilities used by the public parser APIs.
///
/// This is an enum with no cases so it acts only as a namespace: it cannot be
/// instantiated and holds no state. It does not understand the OpenTag3D
/// specification or decode fields. Its only job is converting hexadecimal text
/// into `Data`.
///
/// For example:
///
/// ```swift
/// let data = try OpenTag3DHex.decode("07 D3 50 4C")
/// print(Array(data.prefix(4))) // [7, 211, 80, 76]
/// ```
///
/// Public callers normally use `OpenTag3DParser.parse(hex:)` instead of calling
/// this internal utility. `parse(hex:)` calls `decode(_:)` and then passes the
/// resulting `Data` to `OpenTag3DParser.parse(_:)`, so hexadecimal and binary
/// inputs use the same field-decoding code path.
enum OpenTag3DHex {
    /// Converts hexadecimal text into its exact binary representation.
    ///
    /// Whitespace is ignored, and uppercase and lowercase digits are accepted.
    /// Every byte must contain exactly two hexadecimal digits.
    ///
    /// ```swift
    /// // A real payload normally continues beyond these example bytes.
    /// let data = try OpenTag3DHex.decode("07 d3 50 4c 41 00")
    ///
    /// // Equivalent output, truncated for brevity:
    /// Array(data) // [0x07, 0xD3, 0x50, 0x4C, 0x41, 0x00, ...]
    /// ```
    ///
    /// - Parameter text: Hexadecimal bytes with optional whitespace.
    /// - Returns: One byte of `Data` for every two hexadecimal digits.
    /// - Throws: `OpenTag3DError.invalidHexCharacter` when a non-hexadecimal,
    ///   non-whitespace character is present, or
    ///   `OpenTag3DError.oddHexDigitCount` when the last byte is incomplete.
    static func decode(_ text: String) throws -> Data {
        // Build a list containing only the hex digits. A Swift String is a
        // collection of Character values, so this loop examines one character
        // at a time.
        var hexDigits: [Character] = []

        for character in text {
            if character.isWhitespace {
                continue
            }

            if character.isHexDigit == false {
                throw OpenTag3DError.invalidHexCharacter(character)
            }

            hexDigits.append(character)
        }

        // Two hex digits are required for each byte. For example, "D3" is one
        // byte, while a trailing single "D" is incomplete.
        if hexDigits.count % 2 != 0 {
            throw OpenTag3DError.oddHexDigitCount
        }

        var bytes: [UInt8] = []
        bytes.reserveCapacity(hexDigits.count / 2)
        var digitIndex = 0

        while digitIndex < hexDigits.count {
            // Join the next two characters into a string such as "D3".
            let byteText = String([
                hexDigits[digitIndex],
                hexDigits[digitIndex + 1]
            ])

            // "radix: 16" means that byteText is a base-16 (hexadecimal)
            // number. UInt8(...) returns nil if the string cannot be parsed,
            // so "if let" safely unwraps the returned optional value.
            if let byte = UInt8(byteText, radix: 16) {
                bytes.append(byte)
            } else {
                // Every character was validated above, so this should never
                // occur. Keep the error in case Swift's conversion fails.
                throw OpenTag3DError.invalidSpecification("Unable to decode hexadecimal input.")
            }

            digitIndex += 2
        }

        return Data(bytes)
    }
}

extension Data {
    /// Uppercase hexadecimal with two digits per byte and no separators.
    /// For example, bytes `[0x07, 0xD3]` produce `"07D3"`.
    var openTag3DHex: String {
        var result = ""

        for byte in self {
            result += String(format: "%02X", byte)
        }

        return result
    }
}
