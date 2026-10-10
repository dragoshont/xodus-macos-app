// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// The detected Microsoft Store / Windows package family of an installed game.
///
/// This is a neutral *format* fact derived from on-disk package, manifest and
/// file evidence — never a capability or support verdict. Detecting a type says
/// nothing about whether Xodus can install or run that title.
public enum PackageType: String, Codable, Sendable, CaseIterable {
    case msixvc, win32, appx, eappx, uwp, unknown

    public var label: String {
        switch self {
        case .msixvc: "MSIXVC"
        case .win32: "Win32"
        case .appx: "Appx"
        case .eappx: "EAppx"
        case .uwp: "UWP"
        case .unknown: "Unknown"
        }
    }
}

/// Serializable facts gathered from an installed game folder. This is the only
/// input to `PackageType.classify`; keeping it a pure value makes classification
/// deterministic and fixture-testable without touching the filesystem.
public struct PackageTypeEvidence: Equatable, Codable, Sendable {
    /// A root `MicrosoftGame.config` exists (GDK / Microsoft Store Win32 game).
    public var hasMicrosoftGameConfig: Bool
    /// An `AppxManifest.xml` exists (packaged MSIX/APPX/UWP app).
    public var hasAppxManifest: Bool
    /// The package layout shows an encrypted-APPX marker (`.eappx`/`.eappxbundle`).
    public var encryptedPackageMarker: Bool
    /// Target device families declared by the manifest's `<Dependencies>`.
    public var targetDeviceFamilies: [String]
    /// The manifest declares a full-trust application (`Windows.FullTrustApplication`,
    /// a `runFullTrust` restricted capability, or a `desktop:` extension). Such a
    /// package is a packaged Win32 app, not a sandboxed UWP app.
    public var declaresFullTrustEntryPoint: Bool
    /// A plain Win32 PE executable is present without packaging metadata.
    public var hasWin32Executable: Bool

    public init(hasMicrosoftGameConfig: Bool = false, hasAppxManifest: Bool = false,
                encryptedPackageMarker: Bool = false, targetDeviceFamilies: [String] = [],
                declaresFullTrustEntryPoint: Bool = false, hasWin32Executable: Bool = false) {
        self.hasMicrosoftGameConfig = hasMicrosoftGameConfig
        self.hasAppxManifest = hasAppxManifest
        self.encryptedPackageMarker = encryptedPackageMarker
        self.targetDeviceFamilies = targetDeviceFamilies
        self.declaresFullTrustEntryPoint = declaresFullTrustEntryPoint
        self.hasWin32Executable = hasWin32Executable
    }

    enum CodingKeys: String, CodingKey {
        case hasMicrosoftGameConfig, hasAppxManifest, encryptedPackageMarker
        case targetDeviceFamilies, declaresFullTrustEntryPoint, hasWin32Executable
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        hasMicrosoftGameConfig = try values.decode(Bool.self, forKey: .hasMicrosoftGameConfig)
        hasAppxManifest = try values.decode(Bool.self, forKey: .hasAppxManifest)
        encryptedPackageMarker = try values.decode(Bool.self, forKey: .encryptedPackageMarker)
        targetDeviceFamilies = try values.decode([String].self, forKey: .targetDeviceFamilies)
        declaresFullTrustEntryPoint = try values.decode(Bool.self, forKey: .declaresFullTrustEntryPoint)
        hasWin32Executable = try values.decode(Bool.self, forKey: .hasWin32Executable)
    }
}

extension PackageType {
    /// The universal Windows device family that distinguishes a sandboxed UWP app
    /// from a packaged Win32 (desktop-bridge) app sharing the same manifest schema.
    static let universalDeviceFamily = "windows.universal"

    /// Pure classification from gathered evidence. Precedence is strongest-signal
    /// first: encrypted package, then manifest (UWP vs Appx by full-trust), then a
    /// GDK game config, then a bare Win32 executable, else unknown.
    public static func classify(_ evidence: PackageTypeEvidence) -> PackageType {
        if evidence.encryptedPackageMarker { return .eappx }
        if evidence.hasAppxManifest {
            let universal = evidence.targetDeviceFamilies.contains {
                $0.lowercased() == universalDeviceFamily
            }
            return universal && !evidence.declaresFullTrustEntryPoint ? .uwp : .appx
        }
        if evidence.hasMicrosoftGameConfig { return .msixvc }
        if evidence.hasWin32Executable { return .win32 }
        return .unknown
    }
}
