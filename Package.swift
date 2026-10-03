// swift-tools-version: 6.0
// SPDX-License-Identifier: GPL-3.0-only
import PackageDescription

let package = Package(
    name: "XodusAppFoundation",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "XodusCore", targets: ["XodusCore"]),
        .executable(name: "XodusPreview", targets: ["XodusPreview"]),
        .executable(name: "XodusFixtureChecks", targets: ["XodusFixtureChecks"])
    ],
    targets: [
        .target(name: "XodusCore"),
        .executableTarget(name: "XodusPreview", dependencies: ["XodusCore"],
                          resources: [.copy("Resources/Artwork")]),
        .executableTarget(name: "XodusFixtureChecks", dependencies: ["XodusCore"],
                          path: "Tests/FixtureChecks")
    ]
)
