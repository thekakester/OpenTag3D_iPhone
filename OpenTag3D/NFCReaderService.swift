//
//  NFCReaderService.swift
//  OpenTag3D
//

import CoreNFC
import Foundation

/// Reads an OpenTag3D MIME record from an NDEF-compatible NFC tag.
final class NFCReaderService: NSObject, ObservableObject {
    @Published private(set) var isReading = false
    @Published private(set) var statusMessage = "Enter a hex payload or scan an OpenTag3D tag."
    @Published private(set) var rawHexText = "00 00 00 00"
    @Published private(set) var fieldSections: [OpenTag3DFieldSection] = []

    private var readerSession: NFCNDEFReaderSession?
    private var didFinishCurrentScan = false

    func beginReading() {
        guard NFCNDEFReaderSession.readingAvailable else {
            statusMessage = "NFC reading is not available on this device."
            return
        }

        do {
            _ = try OpenTag3DParser.mimeType()
        } catch {
            statusMessage = "Could not load the OpenTag3D specification: \(error.localizedDescription)"
            return
        }

        didFinishCurrentScan = false
        isReading = true
        statusMessage = "Starting the NFC reader…"

        let session = NFCNDEFReaderSession(
            delegate: self,
            queue: nil,
            invalidateAfterFirstRead: false
        )
        session.alertMessage = "Hold your iPhone near an OpenTag3D filament tag."
        readerSession = session
        session.begin()
    }

    /// Called by the TextEditor every time the user changes the hex dump.
    func updateRawHexText(_ newValue: String) {
        rawHexText = newValue

        do {
            let payload = try refreshDecodedFieldsFromRawHex()
            statusMessage = "Decoded \(payload.count) edited payload bytes."
        } catch {
            fieldSections = []
            statusMessage = "Hex edit error: \(error.localizedDescription)"
        }
    }

    /// Encodes one bubble edit into the payload, then derives every display value again.
    func updateField(id: String, source: OpenTag3DEditSource, text: String) {
        do {
            let currentPayload = try OpenTag3DParser.data(from: rawHexText)
            let updatedPayload = try OpenTag3DParser.replacingField(
                id: id,
                source: source,
                text: text,
                in: currentPayload
            )

            rawHexText = OpenTag3DParser.editableHex(for: updatedPayload)
            try refreshDecodedFieldsFromRawHex()
            statusMessage = "Updated the payload from the edited field."
        } catch {
            statusMessage = "Field edit error: \(error.localizedDescription)"
        }
    }

    /// Rebuilds every displayed field from the current editable hex text.
    @discardableResult
    private func refreshDecodedFieldsFromRawHex() throws -> Data {
        let payload = try OpenTag3DParser.data(from: rawHexText)
        fieldSections = try OpenTag3DParser.fieldSections(from: payload)
        return payload
    }

    private func finishReading(payload: Data) {
        rawHexText = OpenTag3DParser.editableHex(for: payload)

        do {
            try refreshDecodedFieldsFromRawHex()
            statusMessage = "Read an OpenTag3D payload from the NFC tag (\(payload.count) bytes)."
        } catch {
            fieldSections = []
            statusMessage = "The tag was read, but its payload could not be decoded: \(error.localizedDescription)"
        }

        isReading = false
    }
}

extension NFCReaderService: NFCNDEFReaderSessionDelegate {
    func readerSessionDidBecomeActive(_ session: NFCNDEFReaderSession) {
        DispatchQueue.main.async { [weak self] in
            self?.statusMessage = "NFC reader active. Hold the top of your iPhone near the tag."
        }
    }

    func readerSession(
        _ session: NFCNDEFReaderSession,
        didDetectNDEFs messages: [NFCNDEFMessage]
    ) {
        do {
            let mimeType = try OpenTag3DParser.mimeType()
            let matchingRecord = messages
                .flatMap(\.records)
                .first { record in
                    guard record.typeNameFormat == .media,
                          let recordType = String(data: record.type, encoding: .utf8) else {
                        return false
                    }
                    return recordType.caseInsensitiveCompare(mimeType) == .orderedSame
                }

            guard let matchingRecord else {
                didFinishCurrentScan = true
                session.invalidate(
                    errorMessage: "This tag does not contain an application/opentag3d record."
                )
                DispatchQueue.main.async { [weak self] in
                    self?.isReading = false
                    self?.statusMessage = "The tag does not contain an OpenTag3D NDEF record."
                }
                return
            }

            didFinishCurrentScan = true
            session.alertMessage = "OpenTag3D tag read successfully."
            session.invalidate()

            let payload = matchingRecord.payload
            DispatchQueue.main.async { [weak self] in
                self?.finishReading(payload: payload)
            }
        } catch {
            didFinishCurrentScan = true
            session.invalidate(errorMessage: "The OpenTag3D specification could not be loaded.")
            DispatchQueue.main.async { [weak self] in
                self?.isReading = false
                self?.statusMessage = "Could not process the NFC tag: \(error.localizedDescription)"
            }
        }
    }

    func readerSession(
        _ session: NFCNDEFReaderSession,
        didInvalidateWithError error: Error
    ) {
        let scanWasFinished = didFinishCurrentScan

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.readerSession = nil
            self.isReading = false

            guard !scanWasFinished else { return }

            if let readerError = error as? NFCReaderError,
               readerError.code == .readerSessionInvalidationErrorUserCanceled {
                self.statusMessage = "NFC scan canceled."
            } else {
                self.statusMessage = "NFC scan ended: \(error.localizedDescription)"
            }
        }
    }
}
