//
//  OpenTag3DTests.swift
//  OpenTag3DTests
//
//  Created by Mitch Davis (With AI Assistance) on 8/27/26.
//

import Foundation
import OpenTag3DKit
import Testing
@testable import OpenTag3D

struct OpenTag3DTests {
    @Test func appUsesVersionedLibrarySpecification() throws {
        var payload = Data(repeating: 0, count: 0xD8)
        payload[0] = 0x07
        payload[1] = 0xD3

        let parser = try TagPayloadEditor.parser(for: payload)
        let tag = try parser.parse(payload)

        #expect(tag.reportedVersion == 2003)
        #expect(tag.specificationVersion == 2003)
        #expect(tag.mimeType == "application/opentag3d")
        #expect(tag.fields.count == 40)
        #expect(tag["diameter"]?.offset == 0x8C)
        #expect(tag["target_vso"]?.offset == 0x97)
    }

    @Test func editableHexRoundTripsThroughLibrary() throws {
        var payload = Data(repeating: 0, count: 0xD8)
        payload[0] = 0x07
        payload[1] = 0xD3
        payload[0x8C] = 0x06
        payload[0x8D] = 0xD6

        let editableHex = TagPayloadEditor.editableHex(for: payload)
        let reparsedData = try TagPayloadEditor.data(from: editableHex)
        let parser = try TagPayloadEditor.parser(for: reparsedData)
        let diameter = try parser.parse(reparsedData)["diameter"]

        #expect(reparsedData == payload)
        #expect(diameter?.hex == "06D6")
        #expect(diameter?.rawInteger == 1750)
        #expect(diameter?.description == "1.750 mm")
    }

    @Test func humanDiameterEditRoundTripsThroughLibrary() throws {
        var payload = Data(repeating: 0, count: 0xD8)
        payload[0] = 0x07
        payload[1] = 0xD3

        let updated = try TagPayloadEditor.replacingField(
            id: "diameter",
            source: .humanReadable,
            text: "2.85",
            in: payload
        )
        let parser = try TagPayloadEditor.parser(for: updated)
        let diameter = try parser.parse(updated)["diameter"]

        #expect(updated[0x8C] == 0x0B)
        #expect(updated[0x8D] == 0x22)
        #expect(diameter?.rawInteger == 2850)
        #expect(diameter?.description == "2.850 mm")
    }

    @Test func structuredEditsRoundTripThroughLibrary() throws {
        var payload = Data(repeating: 0, count: 0xD8)
        payload[0] = 0x07
        payload[1] = 0xD3
        payload = try TagPayloadEditor.replacingField(
            id: "manufacturer",
            source: .humanReadable,
            text: "Acme",
            in: payload
        )
        payload = try TagPayloadEditor.replacingField(
            id: "color_1",
            source: .humanReadable,
            text: "#11223344",
            in: payload
        )
        payload = try TagPayloadEditor.replacingField(
            id: "mfg_date",
            source: .humanReadable,
            text: "2025-12-31",
            in: payload
        )

        let parser = try TagPayloadEditor.parser(for: payload)
        let tag = try parser.parse(payload)

        #expect(tag["manufacturer"]?.description == "Acme")
        #expect(tag["color_1"]?.hex == "11223344")
        #expect(tag["mfg_date"]?.description == "2025-12-31")
    }
}
