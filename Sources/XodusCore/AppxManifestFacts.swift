// SPDX-License-Identifier: GPL-3.0-only
import Foundation

public struct AppxManifestFacts: Equatable, Sendable {
    public let targetDeviceFamilies: [String]
    public let fullTrust: Bool
    public let uwpApplication: Bool

    public static func parse(_ data: Data) throws -> Self {
        guard !data.isEmpty, data.count <= 1_048_576 else { throw AppxManifestError.invalid }
        let reader = AppxManifestReader()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false
        parser.delegate = reader
        guard parser.parse(), !reader.invalid, reader.root == "Package", reader.applications > 0 else {
            throw AppxManifestError.invalid
        }
        return Self(targetDeviceFamilies: reader.families, fullTrust: reader.fullTrust,
                    uwpApplication: reader.uwpApplication)
    }
}

public enum AppxManifestError: Error { case invalid }

private final class AppxManifestReader: NSObject, XMLParserDelegate {
    var root: String?
    var families: [String] = []
    var fullTrust = false
    var uwpApplication = false
    var applications = 0
    var invalid = false
    private var path: [String] = []

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String]) {
        path.append(name)
        if path.count == 1 { root = name }
        guard path.count <= 64, families.count < 64, applications < 256 else {
            invalid = true; parser.abortParsing(); return
        }
        if path == ["Package", "Dependencies", "TargetDeviceFamily"],
           let family = attributes["Name"], !family.isEmpty, family.utf8.count <= 256 {
            families.append(family)
        }
        if path == ["Package", "Applications", "Application"] {
            applications += 1
            let entryPoint = attributes["EntryPoint"]
            let behavior = attribute("RuntimeBehavior", in: attributes)
            let trust = attribute("TrustLevel", in: attributes)
            if entryPoint == "Windows.FullTrustApplication" || trust == "mediumIL"
                || behavior == "win32App" || behavior == "packagedClassicApp" {
                fullTrust = true
            } else if behavior == "windowsApp" || trust == "appContainer"
                || (behavior == nil && trust == nil && entryPoint?.isEmpty == false) {
                uwpApplication = true
            }
        }
        if path == ["Package", "Capabilities", "Capability"], attributes["Name"] == "runFullTrust" {
            fullTrust = true
        }
        if name == "Extension", attributes["Category"] == "windows.fullTrustProcess" { fullTrust = true }
    }

    private func attribute(_ name: String, in values: [String: String]) -> String? {
        values.first { $0.key.split(separator: ":").last.map(String.init) == name }?.value
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?,
                qualifiedName: String?) {
        path.removeLast()
    }

    func parser(_ parser: XMLParser, foundInternalEntityDeclarationWithName name: String, value: String?) {
        invalid = true; parser.abortParsing()
    }

    func parser(_ parser: XMLParser, foundExternalEntityDeclarationWithName name: String,
                publicID: String?, systemID: String?) {
        invalid = true; parser.abortParsing()
    }
}
