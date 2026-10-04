// swift-tools-version: 6.0
// SPDX-License-Identifier: GPL-3.0-only
import PackageDescription

let package = Package(
    name: "XodusAppFoundation",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "XodusCore", targets: ["XodusCore"]),
        .library(name: "XodusManagement", targets: ["XodusManagement"]),
        .executable(name: "XodusPreview", targets: ["XodusPreview"]),
        .executable(name: "XodusAuthHost", targets: ["XodusAuthHost"]),
        .executable(name: "XodusFixtureChecks", targets: ["XodusFixtureChecks"]),
        .executable(name: "XodusManagementChecks", targets: ["XodusManagementChecks"])
    ],
    targets: [
        .target(name: "XodusCore"),
        .target(name: "XodusManagement", dependencies: ["XodusCore"],
                resources: [.copy("Resources/management-v1.schema.json"),
                            .copy("Resources/runtime-providers-v1.schema.json")]),
        .executableTarget(name: "XodusPreview", dependencies: ["XodusCore", "XodusManagement"],
                          resources: [.copy("Resources/Artwork")]),
        .executableTarget(name: "XodusAuthHost", resources: [.copy("Resources")]),
        .executableTarget(name: "XodusFixtureChecks", dependencies: ["XodusCore"],
                          path: "Tests/FixtureChecks"),
        .executableTarget(name: "XodusManagementChecks", dependencies: ["XodusManagement"],
                          path: "Tests/ManagementChecks", resources: [.copy("Fixtures")])
    ]
)
