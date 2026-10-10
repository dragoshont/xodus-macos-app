// SPDX-License-Identifier: GPL-3.0-only
import Darwin
import Foundation
import XodusCore

enum PackageInspector {
    static func detect(folder: URL) throws -> PackageType {
        PackageType.classify(try inspect(folder: folder))
    }

    static func inspect(folder: URL) throws -> PackageTypeEvidence {
        try InstalledGameFiles.checkFolder(folder)
        let entries = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        var evidence = PackageTypeEvidence()
        var manifests: [URL] = []
        for entry in entries {
            var info = stat()
            guard lstat(entry.path, &info) == 0 else { throw InstalledGameError.invalidConfig }
            guard info.st_mode & S_IFMT == S_IFREG else { continue }
            let name = entry.lastPathComponent.lowercased()
            if name == "microsoftgame.config" { evidence.hasMicrosoftGameConfig = true }
            if name == "appxmanifest.xml" { manifests.append(entry) }
            if name.hasSuffix(".eappx") || name.hasSuffix(".eappxbundle") {
                evidence.encryptedPackageMarker = true
            }
            if name.hasSuffix(".msixvc") {
                evidence.hasMSIXVCHeader = evidence.hasMSIXVCHeader ||
                    PackageType.hasMSIXVCHeader(try readPrefix(entry, maximumBytes: 4096))
            }
            if name.hasSuffix(".exe") {
                evidence.hasWin32Executable = evidence.hasWin32Executable ||
                    PackageType.hasPEHeader(try readPrefix(entry, maximumBytes: 1_048_576))
            }
        }
        guard manifests.count <= 1 else { throw InstalledGameError.invalidConfig }
        if let manifest = manifests.first {
            let facts = try AppxManifestFacts.parse(
                InstalledGameFiles.readRegular(manifest, maximumBytes: 1_048_576))
            evidence.hasAppxManifest = true
            evidence.targetDeviceFamilies = facts.targetDeviceFamilies
            evidence.declaresFullTrustEntryPoint = facts.fullTrust
            evidence.declaresUWPApplication = facts.uwpApplication
        }
        return evidence
    }

    private static func readPrefix(_ url: URL, maximumBytes: Int) throws -> Data {
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { throw InstalledGameError.invalidConfig }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { handle.closeFile() }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG else {
            throw InstalledGameError.invalidConfig
        }
        return try handle.read(upToCount: maximumBytes) ?? Data()
    }
}
