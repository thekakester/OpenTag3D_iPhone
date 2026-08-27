//
//  LandingView.swift
//  OpenTag3D
//

import SwiftUI

struct LandingView: View {
    let onContinue: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(spacing: 10) {
                    Image("PolarFilamentLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 300, minHeight: 90)
                        .accessibilityLabel("Polar Filament")

                    Text("OpenTag3D Dev Tools")
                        .font(.title2.weight(.semibold))
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 12) {
                    Text("About this app")
                        .font(.headline)

                    Text("Polar Filament built this developer tool as a minimal reference implementation of the open-source OpenTag3D standard. Polar Filament uses and implements the standard, but does not own or control it. This is not the official OpenTag3D app.")

                    Text("We hope this project inspires others to build their own RFID-enabled filament tools. The possibilities include inventory management, spool-weight estimation, slicer integration, automatic print profiles, automatic color recognition, and much more.")
                }

                Button(action: onContinue) {
                    Text("Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.top, 8)

                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("References")
                            .font(.headline)

                        Text("Optional resources for learning more or building your own tools.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    ResourceLink(
                        title: "OpenTag3D Specification",
                        detail: "Read the open standard and its complete memory map.",
                        url: URL(string: "https://opentag3d.info")!
                    )

                    ResourceLink(
                        title: "App Source Code",
                        detail: "View this app's source code and contribute on GitHub.",
                        url: URL(string: "https://github.com/thekakester/OpenTag3D_iPhone")!
                    )
                }
            }
            .font(.subheadline)
            .padding()
        }
    }
}

private struct ResourceLink: View {
    let title: String
    let detail: String
    let url: URL

    var body: some View {
        Link(destination: url) {
            HStack(spacing: 12) {
                Image(systemName: "link")
                    .font(.title3)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.caption)
            }
            .padding(12)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    LandingView {}
}
