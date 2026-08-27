# OpenTag3D iPhone Developer Tools

OpenTag3D iPhone Developer Tools is a minimalist iOS app for inspecting and editing OpenTag3D NFC tag data. Polar Filament created it as a small, practical reference implementation and as inspiration for other developers to adopt the OpenTag3D standard in their own projects.

Polar Filament uses and implements OpenTag3D, but does not own or control the standard. This project is not the official OpenTag3D app.

## Purpose

This app is deliberately geared toward developers. It exposes the technical details of an OpenTag3D payload rather than hiding them behind an inventory system or another consumer-facing workflow.

The app is designed to:

- Read an OpenTag3D NDEF payload from an NFC tag.
- Display and edit the complete payload as hexadecimal bytes.
- Decode the CORE and EXTENDED fields defined by the OpenTag3D specification.
- Show field offsets, lengths, raw hexadecimal data, numeric values, and human-readable values.
- Encode edited field values back into the raw payload.
- Write the resulting OpenTag3D payload to an NFC tag.

The raw payload is the app's single source of truth. Editing either the hex dump or a decoded field updates that payload, and all displayed values are then derived from it again.

This app intentionally serves no broader purpose beyond reading, understanding, editing, and writing raw OpenTag3D data. It is meant to be bare-bones code that developers can study, modify, and use as a starting point.

## Why OpenTag3D?

RFID-enabled filament can support far more than identifying a spool. OpenTag3D can provide a common foundation for projects involving inventory management, spool-weight estimation, slicer integration, automatic print profiles, automatic color recognition, and other ideas that have not been built yet.

We hope this project makes the standard easier to explore and encourages people to create their own integrations.

## Why is there no Android version?

There is no separate Android version of this app because compatible Android phones can read and write tags directly from the OpenTag3D website using Web NFC. The native iPhone app provides access to this workflow on iOS, where OpenTag3D's browser-based Web NFC tools are not available.

## Development requirements

> [!WARNING]
> **A paid Apple Developer Program membership is required for NFC development on iPhone.** A free Apple developer account, shown as a **Personal Team** in Xcode, cannot provision an app with the NFC Tag Reading capability. Without a paid membership (or access to a team that has one), you can work on the parser, editor, and interface, but you cannot sign and run this app's NFC read/write functionality on a physical iPhone.

## References

- [Export Polar Filament RFID data from a spool ID](https://pfil.us/rfid)
- [OpenTag3D specification](https://opentag3d.info)
- [Apple's supported iOS capabilities by program membership](https://developer.apple.com/help/account/reference/supported-capabilities-ios)
