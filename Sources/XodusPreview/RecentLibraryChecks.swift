// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import Foundation
import XodusManagement

@MainActor
enum RecentLibraryChecks {
    static func imageChecks(check: (Bool, String) -> Void) throws {
        for (width, height) in [(4096, 4096), (8192, 2048), (1, 1)] {
            try CatalogImagePolicy.validatePixels(width: width, height: height)
            check(true, "Decoded image policy admits exact sixteen-megapixel and axis boundaries")
        }
        for (width, height) in [(4096, 4097), (8192, 2049), (8193, 1), (0, 1), (1, -1)] {
            do {
                try CatalogImagePolicy.validatePixels(width: width, height: height)
                check(false, "Decoded dimensions reject one-pixel overflow and invalid axes before allocation")
            } catch { check(error as? ArtworkLoadError == .oversized,
                            "Decoded dimensions reject one-pixel overflow and invalid axes before allocation") }
        }
        do {
            _ = try CatalogImagePolicy.decode(Data(repeating: 0, count: CatalogImagePolicy.maximumBytes + 1))
            check(false, "Image bytes over eight MiB are rejected before ImageIO")
        } catch { check(error as? ArtworkLoadError == .oversized,
                        "Image bytes over eight MiB are rejected before ImageIO") }
        do {
            _ = try CatalogImagePolicy.decode(Data("not an image".utf8))
            check(false, "Malformed image bytes fail explicitly instead of producing a successful placeholder")
        } catch { check(error as? ArtworkLoadError == .invalidImage,
                        "Malformed image bytes fail explicitly instead of producing a successful placeholder") }
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 32, pixelsHigh: 16,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let pixels = bitmap.bitmapData else {
            throw ArtworkLoadError.invalidImage
        }
        pixels.initialize(repeating: 0, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
        guard let bytes = bitmap.representation(using: .png, properties: [:]) else {
            throw ArtworkLoadError.invalidImage
        }
        let decoded = try CatalogImagePolicy.decode(bytes)
        check(decoded.width == 32 && decoded.height == 16,
              "The actual ImageIO thumbnail path decodes a local synthetic PNG without network access")
    }

    static func run(check: (Bool, String) -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("RecentLibraryChecks-\(UUID())")
        defer {
            do { try FileManager.default.removeItem(at: root) }
            catch { check(false, "Neutral recent-history trace files are cleaned") }
        }
        func configuration(_ scenario: String) -> BackendConfiguration {
            BackendConfiguration(executable: URL(fileURLWithPath: CommandLine.arguments[0])
                .deletingLastPathComponent().appendingPathComponent("XodusManagementChecks"),
                stateDirectory: root.appendingPathComponent(scenario))
        }
        func trace(_ scenario: String) throws -> [String] {
            try String(contentsOf: root.appendingPathComponent(scenario).appendingPathComponent("lifecycle.log"),
                       encoding: .utf8).split(separator: "\n").map(String.init)
        }
        func waitForRead(_ scenario: String, count: Int = 1) async throws {
            let deadline = ContinuousClock.now.advanced(by: .seconds(5))
            while (try trace(scenario)).filter({ $0 == "library.recent" }).count < count {
                guard ContinuousClock.now < deadline else { throw ManagementError.requestTimedOut }
                try await Task.sleep(for: .milliseconds(10))
            }
        }
        let session = LiveSession(configuration: configuration("recentslow"))
        await session.connect()
        await session.refreshRecentLibrary()
        let uncheckedTrace = try trace("recentslow")
        check(session.recentLibrary == nil && !session.canRefreshRecentLibrary
              && !uncheckedTrace.contains("auth.status")
              && !uncheckedTrace.contains("library.recent"),
              "Anonymous startup and an unchecked Library never read credentials or personal history")
        await session.refreshAccount()
        let confirmedTrace = try trace("recentslow")
        check(session.canRefreshRecentLibrary && session.recentLibrary == nil
              && !confirmedTrace.contains("library.recent"),
              "Foreground Account confirmation enables an explicit history read, not automatic collection")
        let reading = Task { await session.refreshRecentLibrary() }
        try await waitForRead("recentslow")
        check(session.recentLibraryLoading && session.accountBusy && !session.canDisconnectAccount,
              "A personal-history request leases account mutations until its actual result")
        await session.refreshRecentLibrary()
        await session.refreshAccount()
        await session.beginSignIn()
        await session.refreshCatalog("neutral")
        check(session.products.count == 1 && session.recentLibraryLoading,
              "Public catalog work remains responsive during the single personal-history read")
        await reading.value
        check(try trace("recentslow").filter { $0 == "library.recent" }.count == 1
              && trace("recentslow").filter { $0 == "auth.status" }.count == 1
              && !trace("recentslow").contains("auth.begin"),
              "Repeated Library/Account clicks cannot redispatch or initiate login while reading")
        check(session.recentLibrary?.titles.count == 1 && session.recentLibraryCurrent
              && !session.recentLibraryLoading && !session.accountBusy
              && session.recentLibrary?.titles.first?.productID == nil,
              "Real-shaped history publishes separately from public product and installed evidence")
        await session.refreshAccount()
        let clearedTrace = try trace("recentslow")
        check(session.recentLibrary == nil && !session.recentLibraryCurrent
              && clearedTrace.filter { $0 == "library.recent" }.count == 1,
              "Explicit Account refresh clears identity-unbound personal history without rereading it")
        await session.refreshRecentLibrary()
        await session.signOut()
        check(session.recentLibrary == nil && !session.recentLibraryCurrent
              && session.currentCredentialState == .signedOut,
              "Sign-out clears personal history and does not reload it")
        check(await session.disconnect(), "Neutral history owner closes")

        let uncertain = LiveSession(configuration: configuration("recentstatusslow"))
        await uncertain.connect()
        await uncertain.refreshAccount()
        await uncertain.refreshRecentLibrary()
        let statusRead = Task { await uncertain.refreshAccount() }
        let statusDeadline = ContinuousClock.now.advanced(by: .seconds(5))
        while try trace("recentstatusslow").filter({ $0 == "auth.status" }).count < 2 {
            guard ContinuousClock.now < statusDeadline else { throw ManagementError.requestTimedOut }
            try await Task.sleep(for: .milliseconds(10))
        }
        check(uncertain.recentLibrary == nil && !uncertain.recentLibraryCurrent
              && uncertain.accountStatusChecking && uncertain.accountBusy,
              "Identity-unbound history disappears before a new foreground saved-status read returns")
        await statusRead.value
        check(try trace("recentstatusslow").filter { $0 == "library.recent" }.count == 1
              && uncertain.recentLibrary == nil,
              "Credential-present status never silently rereads or rebinds earlier personal history")
        check(await uncertain.disconnect(), "Neutral foreground privacy-check owner closes")

        for scenario in ["recentstale", "recentprofilechanged", "recentzero"] {
            let value = LiveSession(configuration: configuration(scenario))
            await value.connect()
            await value.refreshAccount()
            await value.refreshRecentLibrary()
            if scenario == "recentzero" {
                check(value.recentLibrary?.titles.isEmpty == true && value.recentLibraryCurrent
                      && value.recentLibraryError == nil,
                      "An actual zero-title result is distinct from unsupported, unchecked and failed history")
            } else {
                await value.refreshRecentLibrary()
                check(value.recentLibraryError != nil && !value.recentLibraryCurrent,
                      "A failed personal read surfaces an actionable error, never successful empty history")
                check(scenario == "recentstale"
                      ? value.recentLibrary?.titles.count == 1 && value.accountStatusCurrent
                        && value.recentLibraryNotice?.contains("previously checked") == true
                      : value.recentLibrary == nil && !value.accountStatusCurrent,
                      "Transport failure retains explicitly stale history; a changed profile clears it")
            }
            check(await value.disconnect(), "Neutral failure/empty history owner closes")
        }
        let retired = LiveSession(configuration: configuration("recentslow"))
        await retired.connect()
        await retired.refreshAccount()
        let previousReads = try trace("recentslow").filter { $0 == "library.recent" }.count
        let late = Task { await retired.refreshRecentLibrary() }
        try await waitForRead("recentslow", count: previousReads + 1)
        check(await retired.disconnect(), "In-flight history owner retires without a second profile owner")
        await late.value
        check(retired.recentLibrary == nil && !retired.recentLibraryCurrent && !retired.accountBusy,
              "Retired generations cannot publish late personal results")
        check(!RecentPlatformFilter.pc.includes(.console) && !RecentPlatformFilter.pc.includes(.unknown)
              && RecentPlatformFilter.pc.includes(.mixed) && RecentPlatformFilter.pc.includes(.pc),
              "PC filtering uses reported platform evidence, never all Xbox history")
    }
}
