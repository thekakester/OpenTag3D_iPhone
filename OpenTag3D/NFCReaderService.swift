//
//  NFCReaderService.swift
//  OpenTag3D
//

import CoreNFC
import Foundation

/// Owns the Core NFC session and publishes scan results for SwiftUI.
final class NFCReaderService: NSObject, ObservableObject {
    static let openTag3DMIMEType = "application/OpenTag3D"

    @Published private(set) var isScanning = false
    @Published private(set) var statusMessage = "Ready to scan an OpenTag3D tag."
    @Published private(set) var uidHex: String?
    @Published private(set) var payloadsHex: [String] = []

    private var session: NFCTagReaderSession?
    private var isFinishingProgrammatically = false

    func beginScanning() {
        guard NFCReaderSession.readingAvailable else {
            statusMessage = "NFC reading is not available on this device."
            return
        }

        uidHex = nil
        payloadsHex = []
        isFinishingProgrammatically = false
        isScanning = true
        statusMessage = "Hold the top of your iPhone near the NFC tag."

        session = NFCTagReaderSession(
            pollingOption: .iso14443,
            delegate: self,
            queue: nil
        )
        session?.alertMessage = "Hold the top of your iPhone near an OpenTag3D tag."
        session?.begin()
    }

    private func publish(
        uid: Data? = nil,
        payloads: [Data]? = nil,
        status: String? = nil,
        scanning: Bool? = nil
    ) {
        DispatchQueue.main.async {
            if let uid {
                self.uidHex = Self.hexString(for: uid)
            }
            if let payloads {
                self.payloadsHex = payloads.map(Self.hexDump(for:))
            }
            if let status {
                self.statusMessage = status
            }
            if let scanning {
                self.isScanning = scanning
            }
        }
    }

    private static func openTag3DPayloads(in message: NFCNDEFMessage) -> [Data] {
        message.records.compactMap { record in
            guard record.typeNameFormat == .media,
                  let recordType = String(data: record.type, encoding: .utf8),
                  recordType.caseInsensitiveCompare(openTag3DMIMEType) == .orderedSame else {
                return nil
            }

            return record.payload
        }
    }

    private static func hexString(for data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    private static func hexDump(for data: Data) -> String {
        guard !data.isEmpty else { return "(empty payload)" }

        return stride(from: 0, to: data.count, by: 16).map { offset in
            let end = min(offset + 16, data.count)
            let bytes = data[offset..<end]
                .map { String(format: "%02X", $0) }
                .joined(separator: " ")
            return String(format: "%04X  %@", offset, bytes)
        }
        .joined(separator: "\n")
    }

    private func finish(_ session: NFCTagReaderSession, alertMessage: String) {
        isFinishingProgrammatically = true
        session.alertMessage = alertMessage
        session.invalidate()
    }
}

extension NFCReaderService: NFCTagReaderSessionDelegate {
    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {
        publish(status: "Scanning for a tag…")
    }

    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        self.session = nil

        if isFinishingProgrammatically {
            isFinishingProgrammatically = false
            publish(scanning: false)
            return
        }

        if let readerError = error as? NFCReaderError,
           readerError.code == .readerSessionInvalidationErrorUserCanceled {
            publish(status: "Scan canceled.", scanning: false)
            return
        }

        publish(status: "NFC session ended: \(error.localizedDescription)", scanning: false)
    }

    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        guard tags.count == 1 else {
            session.alertMessage = "More than one tag was detected. Move the others away and try again."
            session.restartPolling()
            return
        }

        guard case let .miFare(tag) = tags[0] else {
            publish(status: "Unsupported tag type.", scanning: false)
            finish(session, alertMessage: "This is not a supported NFC Type 2/MIFARE tag.")
            return
        }

        let uid = tag.identifier
        publish(uid: uid, status: "Tag found. Reading its NDEF message…")

        session.connect(to: tags[0]) { [weak self] error in
            guard let self else { return }

            if let error {
                self.publish(status: "Connection failed: \(error.localizedDescription)", scanning: false)
                self.finish(session, alertMessage: "Could not connect to the tag.")
                return
            }

            tag.queryNDEFStatus { status, _, error in
                if let error {
                    self.publish(status: "NDEF inspection failed: \(error.localizedDescription)", scanning: false)
                    self.finish(session, alertMessage: "Could not inspect the tag's NDEF data.")
                    return
                }

                guard status != .notSupported else {
                    self.publish(status: "UID read; no NDEF message is available.", scanning: false)
                    self.finish(session, alertMessage: "UID read, but this tag is not NDEF formatted.")
                    return
                }

                tag.readNDEF { message, error in
                    if let error {
                        self.publish(status: "NDEF read failed: \(error.localizedDescription)", scanning: false)
                        self.finish(session, alertMessage: "UID read, but the NDEF message could not be read.")
                        return
                    }

                    guard let message else {
                        self.publish(status: "UID read; the NDEF message was empty.", scanning: false)
                        self.finish(session, alertMessage: "UID read, but the tag returned no NDEF message.")
                        return
                    }

                    let payloads = Self.openTag3DPayloads(in: message)
                    if payloads.isEmpty {
                        self.publish(
                            payloads: [],
                            status: "UID read; no application/OpenTag3D record was found.",
                            scanning: false
                        )
                        self.finish(
                            session,
                            alertMessage: "Tag read. No application/OpenTag3D record was found."
                        )
                    } else {
                        self.publish(
                            payloads: payloads,
                            status: "Read \(payloads.count) OpenTag3D record\(payloads.count == 1 ? "" : "s").",
                            scanning: false
                        )
                        self.finish(session, alertMessage: "OpenTag3D record read successfully.")
                    }
                }
            }
        }
    }
}
