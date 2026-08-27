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

    @Test func decodesCoreAndExtendedFields() throws {
        let hex = "00 00 " + String(repeating: "00 ", count: 185)
        let data = try OpenTag3DParser.data(from: hex)
        let fields = OpenTag3DParser.fields(from: data)

        #expect(fields.filter { $0.section == .core }.count == 15)
        #expect(fields.filter { $0.section == .extended }.count == 21)
        #expect(fields.first { $0.id == "target_diameter" }?.offset == 0x5C)
        #expect(fields.first { $0.id == "target_vso" }?.offset == 0xBA)
    }

    @Test func editingHexChangesDecodedDiameter() throws {
        var bytes = Data(repeating: 0, count: 0xBB)
        bytes[0x5C] = 0x06
        bytes[0x5D] = 0xD6

        let editableHex = OpenTag3DParser.editableHex(for: bytes)
        let reparsedData = try OpenTag3DParser.data(from: editableHex)
        let diameter = OpenTag3DParser.fields(from: reparsedData)
            .first { $0.id == "target_diameter" }

        #expect(diameter?.rawHex == "06 D6")
        #expect(diameter?.numericValue == "1750")
        #expect(diameter?.humanReadableValue == "1.750 mm")
    }

    @Test func humanDiameterEditRoundTripsThroughPayload() throws {
        let original = Data(repeating: 0, count: 0xBB)
        let updated = try OpenTag3DParser.replacingField(
            id: "target_diameter",
            source: .humanReadable,
            text: "2.85",
            in: original
        )
        let diameter = OpenTag3DParser.fields(from: updated)
            .first { $0.id == "target_diameter" }

        #expect(updated[0x5C] == 0x0B)
        #expect(updated[0x5D] == 0x22)
        #expect(diameter?.numericValue == "2850")
        #expect(diameter?.rawHex == "0B 22")
        #expect(diameter?.humanReadableValue == "2.850 mm")
    }

    @Test func numericAndRawHexEditsRoundTrip() throws {
        let original = Data(repeating: 0, count: 0xBB)
        let numericUpdate = try OpenTag3DParser.replacingField(
            id: "target_diameter",
            source: .numeric,
            text: "2850",
            in: original
        )
        let rawHexUpdate = try OpenTag3DParser.replacingField(
            id: "target_diameter",
            source: .rawHex,
            text: "0B 22",
            in: original
        )

        #expect(numericUpdate == rawHexUpdate)
    }

    @Test func structuredFieldEditsRoundTrip() throws {
        var payload = Data(repeating: 0, count: 0xBB)
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

        let fields = OpenTag3DParser.fields(from: payload)
        #expect(fields.first { $0.id == "manufacturer" }?.humanReadableValue == "Acme")
        #expect(fields.first { $0.id == "color_1" }?.rawHex == "11 22 33 44")
        #expect(fields.first { $0.id == "mfg_date" }?.humanReadableValue == "2025-12-31")
        #expect(fields.first { $0.id == "mfg_time" }?.humanReadableValue == "23:59:58 UTC")
    }

}
