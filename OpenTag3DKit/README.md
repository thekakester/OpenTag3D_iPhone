# OpenTag3DKit

`OpenTag3DKit` is a small, data-driven Swift library for parsing OpenTag3D
payloads. It does not read NFC tags, display a user interface, access the
network, or depend on `CoreNFC` or `SwiftUI`.

The package includes the official OpenTag3D 2.003 specification as
`spec-2003.json`. A caller can supply another version of the specification as
JSON without modifying the parser.

## Parse binary data

An NFC implementation should pass only the payload of the
`application/opentag3d` NDEF record:

```swift
import OpenTag3DKit

let parser = try OpenTag3DParser()
let tag = try parser.parse(ndefRecordPayload)

print(tag.reportedVersion)                 // 2003
print(tag["manufacturer"]?.description)   // Polar Filament
print(tag["diameter"]?.description)       // 1.750 mm
print(tag["diameter"]?.rawInteger)        // Optional(1750)
print(tag["diameter"]?.hex)               // 06D6
print(tag["diameter"]?.bytes)             // [6, 214]
```

## Parse hexadecimal text

Whitespace is optional and ignored:

```swift
let tag = try parser.parse(hex: "07 D3 50 4C 41 00 00 ...")
```

The complete payload is available in three forms:

```swift
tag.data   // Foundation.Data
tag.bytes  // [UInt8]
tag.hex    // "07D3504C410000..."
```

## Read the version before parsing

The first two bytes always contain the integer OpenTag3D version. Reading them
does not require a specification:

```swift
let version = try OpenTag3DHeader.version(from: payload)
print(version) // 2003

let versionFromHex = try OpenTag3DHeader.version(fromHex: "07 D3 FF FF")
print(versionFromHex) // 2003
```

This value can select a versioned specification such as `spec-2003.json`.

## Use another specification

Supply either the JSON itself or the URL of a JSON file:

```swift
let parserFromData = try OpenTag3DParser(
    specificationJSON: downloadedSpecification
)

let parserFromFile = try OpenTag3DParser(
    specificationURL: specificationFileURL
)
```

The specification version must match the integer stored in the payload's first
two bytes. A mismatch throws `OpenTag3DError.versionMismatch`.

## Decoded fields

Each `OpenTag3DField` provides:

- Specification metadata: `id`, `name`, `offset`, `length`,
  `type`, `unit`, `addedVersion`, `usage`, `isRequired`, and `documentation`.
- A typed `value`, such as `.integer`, `.number`, `.text`, `.color`, `.date`,
  or `.time`.
- The original unscaled integer in `rawInteger`, when applicable.
- A display-ready `description`.
- The encoded field bytes through `data`, `bytes`, and `hex`.

Fields can be accessed by ID:

```swift
if let diameter = tag.field(id: "diameter") {
    print(diameter.offset)       // 140
    print(diameter.length)       // 2
    print(diameter.rawInteger)   // Optional(1750)
    print(diameter.description)  // 1.750 mm
}
```

When a payload ends before fields defined by the specification, OpenTag3DKit
treats the missing trailing bytes as zero. The original unpadded payload remains
available in `tag.data`.
