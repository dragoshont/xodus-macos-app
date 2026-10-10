// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import XodusCore

/// Gathers on-disk package evidence from an installed game folder and reduces it
/// to a `PackageType`. All reads go through the hardened `InstalledGameFiles`
/// helpers; nothing is executed and no network is touched. The actual
/// classification is the pure `PackageType.classify`, so detection stays testable.
enum PackageInspector {
    static let maximumManifestBytes = 1_048_576

    /// Inspect a folder and return the detected package type. Returns `.unknown`
    /// when the folder cannot be read rather than throwing — detection is a
    /// best-effort fact, never a launch gate.
    static func detect(folder: URL) -> PackageType {
        PackageType.classify(inspect(folder: folder))
    }

    static func inspect(folder: URL) -> PackageTypeEvidence {
        guard (try? InstalledGameFiles.checkFolder(folder)) != nil else { return PackageTypeEvidence() }
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.isRegularFileKey])) ?? []
        var evidence = PackageTypeEvidence()
        var manifestURL: URL?
        for entry in entries {
            let name = entry.lastPathComponent.lowercased()
            if name == "microsoftgame.config" { evidence.hasMicrosoftGameConfig = true }
            if name == "appxmanifest.xml" { evidence.hasAppxManifest = true; manifestURL = entry }
            if name.hasSuffix(".eappx") || name.hasSuffix(".eappxbundle") { evidence.encryptedPackageMarker = true }
            if name.hasSuffix(".exe") { evidence.hasWin32Executable = true }
        }
        if let manifestURL, let manifest = try? readManifest(manifestURL) {
            evidence.targetDeviceFamilies = manifest.targetDeviceFamilies
            evidence.declaresFullTrustEntryPoint = manifest.fullTrust
        }
        return evidence
    }

    private static func readManifest(_ url: URL) throws -> AppxManifestFacts {
        let data = try InstalledGameFiles.readRegular(url, maximumBytes: maximumManifestBytes)
        return try AppxManifestFacts.parse(data)
    }
}

/// The subset of `AppxManifest.xml` facts that distinguish UWP, packaged Win32
/// (desktop bridge / full-trust) and plain Appx packages.
struct AppxManifestFacts: Equatable, Sendable {
    let targetDeviceFamilies: [String]
    let fullTrust: Bool

    static func parse(_ data: Data) throws -> Self {
        guard !data.isEmpty, data.count <= PackageInspector.maximumManifestBytes else {
            throw InstalledGameError.invalidConfig
        }
        let reader = ManifestReader()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false
        parser.delegate = reader
        guard parser.parse(), !reader.invalid else { throw InstalledGameError.invalidConfig }
        return Self(targetDeviceFamilies: reader.targetDeviceFamilies, fullTrust: reader.fullTrust)
    }
}

private final class ManifestReader: NSObject, XMLParserDelegate {
    var targetDeviceFamilies: [String] = []
    var fullTrust = false
    var invalid = false
    private var depth = 0

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes: [String: String]) {
        depth += 1
        guard depth <= 64, targetDeviceFamilies.count <= 64 else { invalid = true; parser.abortParsing(); return }
        switch elementName {
        case "TargetDeviceFamily":
            if let name = attributes["Name"]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !name.isEmpty, name.utf8.count <= 256 {
                targetDeviceFamilies.append(name)
            }
        case "Application":
            if attributes["EntryPoint"] == "Windows.FullTrustApplication" { fullTrust = true }
        case "Capability":
            // `rescap:Capability Name="runFullTrust"` marks a packaged Win32 app.
            if attributes["Name"] == "runFullTrust" { fullTrust = true }
        case "Extension":
            if let category = attributes["Category"]?.lowercased(),
               category.contains("fulltrust") { fullTrust = true }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        depth -= 1
    }

    func parser(_ parser: XMLParser, foundInternalEntityDeclarationWithName name: String, value: String?) {
        invalid = true
        parser.abortParsing()
    }

    func parser(_ parser: XMLParser, foundExternalEntityDeclarationWithName name: String,
                publicID: String?, systemID: String?) {
        invalid = true
        parser.abortParsing()
    }
}
