//
//  OpenTag3DTests.swift
//  OpenTag3DTests
//
//  Created by Mitch Davis (With AI Assistance) on 8/27/26.
//

import Foundation
import Testing
@testable import OpenTag3D

struct OpenTag3DTests {

    @Test func buildsFieldsFromBundledSpecification() throws {
        let hex = String(repeating: "00 ", count: 0xE0)
        let data = try OpenTag3DParser.data(from: hex)
        let sections = try OpenTag3DParser.fieldSections(from: data)
        let fields = sections.flatMap(\.fields)

        #expect(try OpenTag3DParser.specificationVersion() == "2.000")
        #expect(try OpenTag3DParser.mimeType() == "application/opentag3d")
        #expect(sections.map(\.title) == ["CORE"])
        #expect(fields.count == 40)
        #expect(fields.first { $0.id == "diameter" }?.offset == 0x8C)
        #expect(fields.first { $0.id == "target_vso" }?.offset == 0x97)
    }

    @Test func editingHexChangesDecodedDiameter() throws {
        var bytes = Data(repeating: 0, count: 0xE0)
        bytes[0x8C] = 0x06
        bytes[0x8D] = 0xD6

        let editableHex = OpenTag3DParser.editableHex(for: bytes)
        let reparsedData = try OpenTag3DParser.data(from: editableHex)
        let diameter = try OpenTag3DParser.fieldSections(from: reparsedData)
            .flatMap(\.fields)
            .first { $0.id == "diameter" }

        #expect(diameter?.rawHex == "06 D6")
        #expect(diameter?.numericValue == "1750")
        #expect(diameter?.humanReadableValue == "1.750 mm")
    }

    @Test func humanDiameterEditRoundTripsThroughPayload() throws {
        let original = Data(repeating: 0, count: 0xE0)
        let updated = try OpenTag3DParser.replacingField(
            id: "diameter",
            source: .humanReadable,
            text: "2.85",
            in: original
        )
        let diameter = try OpenTag3DParser.fieldSections(from: updated)
            .flatMap(\.fields)
            .first { $0.id == "diameter" }

        #expect(updated[0x8C] == 0x0B)
        #expect(updated[0x8D] == 0x22)
        #expect(diameter?.numericValue == "2850")
        #expect(diameter?.rawHex == "0B 22")
        #expect(diameter?.humanReadableValue == "2.850 mm")
    }

    @Test func numericAndRawHexEditsRoundTrip() throws {
        let original = Data(repeating: 0, count: 0xE0)
        let numericUpdate = try OpenTag3DParser.replacingField(
            id: "diameter",
            source: .numeric,
            text: "2850",
            in: original
        )
        let rawHexUpdate = try OpenTag3DParser.replacingField(
            id: "diameter",
            source: .rawHex,
            text: "0B 22",
            in: original
        )

        #expect(numericUpdate == rawHexUpdate)
    }

    @Test func structuredFieldEditsRoundTrip() throws {
        var payload = Data(repeating: 0, count: 0xE0)
        payload = try OpenTag3DParser.replacingField(
            id: "manufacturer",
            source: .humanReadable,
            text: "Acme",
            in: payload
        )
        payload = try OpenTag3DParser.replacingField(
            id: "color_1",
            source: .humanReadable,
            text: "#11223344",
            in: payload
        )
        payload = try OpenTag3DParser.replacingField(
            id: "mfg_date",
            source: .humanReadable,
            text: "2025-12-31",
            in: payload
        )
        payload = try OpenTag3DParser.replacingField(
            id: "mfg_time",
            source: .humanReadable,
            text: "23:59:58",
            in: payload
        )

        let fields = try OpenTag3DParser.fieldSections(from: payload).flatMap(\.fields)
        #expect(fields.first { $0.id == "manufacturer" }?.humanReadableValue == "Acme")
        #expect(fields.first { $0.id == "color_1" }?.rawHex == "11 22 33 44")
        #expect(fields.first { $0.id == "mfg_date" }?.humanReadableValue == "2025-12-31")
        #expect(fields.first { $0.id == "mfg_time" }?.humanReadableValue == "23:59:58 UTC")
    }

}
