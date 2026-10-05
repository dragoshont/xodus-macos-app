// swift-tools-version: 6.0
// SPDX-License-Identifier: GPL-3.0-only
import PackageDescription
import Foundation

let shipping = ProcessInfo.processInfo.environment["XODUS_SHIPPING"] == "1"
let previewOnly = ["Artwork.swift", "RootView.swift", "DetailView.swift", "DownloadsView.swift",
                   "PreviewExporter.swift", "PreviewChecks.swift", "NativeChecks.swift",
                   "NativeUIChecks.swift", "ApplicationTerminationChecks.swift", "Resources"]
let shippingSettings: [SwiftSetting] = shipping ? [.define("XODUS_SHIPPING")] : []

let package = Package(
    name: "XodusAppFoundation",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "XodusCore", targets: ["XodusCore"]),
        .library(name: "XodusManagement", targets: ["XodusManagement"]),
        .executable(name: "XodusPreview", targets: ["XodusPreview"]),
        .executable(name: "XodusAuthHost", targets: ["XodusAuthHost"])
    ] + (shipping ? [] : [
        .executable(name: "XodusFixtureChecks", targets: ["XodusFixtureChecks"]),
        .executable(name: "XodusManagementChecks", targets: ["XodusManagementChecks"])
    ]),
    targets: [
        .target(name: "XodusCore", exclude: shipping ? ["Fixtures.swift"] : [],
                swiftSettings: shippingSettings),
        .target(name: "XodusManagement", dependencies: ["XodusCore"],
                resources: [.copy("Resources/management-v1.schema.json"),
                            .copy("Resources/runtime-providers-v1.schema.json")]),
        .executableTarget(name: "XodusPreview", dependencies: ["XodusCore", "XodusManagement"],
                          exclude: shipping ? previewOnly : [],
                          resources: shipping ? [] : [.copy("Resources/Artwork")],
                          swiftSettings: shippingSettings),
        .executableTarget(name: "XodusAuthHost", exclude: shipping ? ["AuthHostChecks.swift", "Resources"] : [],
                          resources: shipping ? [] : [.copy("Resources")], swiftSettings: shippingSettings)
    ] + (shipping ? [
        .testTarget(name: "XodusShippingChecks", dependencies: ["XodusPreview", "XodusManagement"],
                    path: "Tests/ShippingChecks")
    ] : [
        .executableTarget(name: "XodusFixtureChecks", dependencies: ["XodusCore"],
                          path: "Tests/FixtureChecks"),
        .executableTarget(name: "XodusManagementChecks", dependencies: ["XodusManagement"],
                          path: "Tests/ManagementChecks", resources: [.copy("Fixtures")])
    ])
)
