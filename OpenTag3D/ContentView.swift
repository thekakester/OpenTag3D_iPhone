//
//  ContentView.swift
//  OpenTag3D
//
//  Created by Mitch Davis on 8/27/26.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var nfcReader = NFCReaderService()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Label("Hello, Polar Filament!", systemImage: "wave.3.right.circle.fill")
                        .font(.title2.bold())
                        .foregroundStyle(.tint)

                    Button {
                        nfcReader.beginScanning()
                    } label: {
                        Label(
                            nfcReader.isScanning ? "Scanning…" : "Read Tag",
                            systemImage: "wave.3.right"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(nfcReader.isScanning)

                    Text(nfcReader.statusMessage)
                        .foregroundStyle(.secondary)

                    if let uidHex = nfcReader.uidHex {
                        ResultSection(title: "Tag UID", value: uidHex)
                    }

                    ForEach(Array(nfcReader.payloadsHex.enumerated()), id: \.offset) { index, payload in
                        ResultSection(
                            title: nfcReader.payloadsHex.count == 1
                                ? "application/OpenTag3D payload"
                                : "application/OpenTag3D payload \(index + 1)",
                            value: payload
                        )
                    }
                }
                .padding()
            }
            .navigationTitle("OpenTag3D")
        }
    }
}

private struct ResultSection: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            Text(value)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
        }
    }
}

#Preview {
    ContentView()
}
