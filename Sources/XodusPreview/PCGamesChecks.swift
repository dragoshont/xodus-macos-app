// SPDX-License-Identifier: GPL-3.0-only
import Foundation

private actor PCGamesMockTransport: PCGamesTransport {
    var responses: [PCGamesHTTPResponse]
    private(set) var requests: [URLRequest] = []

    init(_ responses: [PCGamesHTTPResponse]) { self.responses = responses }

    func send(_ request: URLRequest) throws -> PCGamesHTTPResponse {
        try Task.checkCancellation()
        requests.append(request)
        guard !responses.isEmpty else { throw PCGamesError.transport }
        return responses.removeFirst()
    }

    func append(_ more: [PCGamesHTTPResponse]) { responses += more }
}

private actor PCGamesMockStore: PCGamesRefreshStore {
    var token: String?
    private(set) var saved: [String] = []
    private(set) var reads = 0
    private(set) var deletions = 0
    var deletionFails = false

    init(_ token: String? = nil) { self.token = token }
    func contains() -> Bool { token != nil }
    func read() -> String? { reads += 1; return token }
    func save(_ refreshToken: String) throws {
        try Task.checkCancellation()
        token = refreshToken
        saved.append(refreshToken)
    }
    func delete() throws {
        deletions += 1
        if deletionFails { throw PCGamesError.keychain(-1) }
        token = nil
    }
    func refuseDeletion() { deletionFails = true }
}

private actor PCGamesMockSleeper {
    private(set) var intervals: [Duration] = []
    func sleep(_ value: Duration) { intervals.append(value) }
}

@MainActor
enum PCGamesChecks {
    static func run(check: (Bool, String) -> Void) async throws {
        func response(_ value: [String: Any], status: Int = 200) throws -> PCGamesHTTPResponse {
            PCGamesHTTPResponse(status: status, data: try JSONSerialization.data(withJSONObject: value))
        }
        func item(_ id: String, kind: String = "Game", status: String = "Active", trial: Bool = false) -> [String: Any] {
            ["productId": id, "productKind": kind, "status": status, "isTrial": trial,
             "ignoredProviderField": "not an entitlement"]
        }
        func page(_ items: [[String: Any]], cursor: String? = nil) throws -> PCGamesHTTPResponse {
            var value: [String: Any] = ["items": items]
            if let cursor { value["continuationToken"] = cursor }
            return try response(value)
        }
        func catalogProduct(_ id: String, platform: String = "Windows.Desktop", title: String = "Neutral Game") -> [String: Any] {
            ["ProductId": id,
             "LocalizedProperties": [["ProductTitle": title, "Images": [
                ["ImagePurpose": "Poster", "Uri": "//store-images.s-microsoft.com/image/poster", "Width": 100, "Height": 200],
                ["ImagePurpose": "BoxArt", "Uri": "//store-images.s-microsoft.com/image/square", "Width": 100, "Height": 100]]]],
             "DisplaySkuAvailabilities": [["Sku": ["Properties": ["Packages": [
                ["PlatformDependencies": [["PlatformName": platform]]]]]]]]]
        }
        func authResponses(uhs: String = "123", storeUHS: String = "123") throws -> [PCGamesHTTPResponse] {
            [try response(["Token": "neutral-user", "DisplayClaims": ["xui": [["uhs": uhs]]]]),
             try response(["Token": "neutral-xbox", "DisplayClaims": ["xui": [["uhs": uhs, "xid": "456"]]]]),
             try response(["Token": "neutral-store", "DisplayClaims": ["xui": [["uhs": storeUHS]]]])]
        }
        let first = "FIXTURE00001", second = "FIXTURE00002", third = "FIXTURE00003"
        let fixturePage = try page([item(first), item(first), item(second, status: "Expired"), item(third, trial: true)])
        let parsed = try JSONDecoder().decode(PCGamesCollectionPage.self, from: fixturePage.data)
        check(parsed.items.filter(\.isCandidate).map(\.productId) == [first, first],
              "S4: Only exact Game/Active/non-trial rows are candidates; dedupe happens across pages")
        let missingTrial = try response(["items": [["productId": first, "productKind": "Game", "status": "Active"]]])
        check(try JSONDecoder().decode(PCGamesCollectionPage.self, from: missingTrial.data).items.first?.isCandidate == true,
              "S4: Absent isTrial is not invented trial evidence")
        let alternateID = try response(["items": [["ProductId": first, "productKind": "Game", "status": "Active"]]])
        check(try JSONDecoder().decode(PCGamesCollectionPage.self, from: alternateID.data).items.first?.productId == first,
              "S4: Approved ProductId fallback preserves exact ID without guessing")
        for invalid: [String: Any] in [
            [:], ["items": NSNull()], ["items": "unexpected"],
            ["items": [["productId": first, "productKind": "Game", "status": "Active", "isTrial": "false"]]],
            ["items": [["productId": first, "productKind": "Game"]]],
            ["items": [], "continuationToken": 1]
        ] {
            do {
                _ = try JSONDecoder().decode(PCGamesCollectionPage.self, from: response(invalid).data)
                check(false, "S4: Malformed required collection data is rejected")
            } catch { check(true, "S4: Malformed required collection data is rejected") }
        }
        let transport = PCGamesMockTransport(try authResponses() + [
            page([item(first), item(second, kind: "Application"), item(third, trial: true)], cursor: "neutral-next"),
            page([item(first), item("FIXTURE00004"), item("FIXTURE00005"), item("FIXTURE00006")]),
            response(["Products": [catalogProduct(first),
                                   catalogProduct("FIXTURE00004", platform: "Xbox.One"),
                                   catalogProduct("FIXTURE00005", platform: "windows.desktop")]])])
        let snapshot = try await PCGamesClient(transport: transport).library(
            accessToken: "neutral-access", market: "GB", language: "en-GB")
        check(snapshot.games.map(\.id) == [first] && snapshot.excludedCount == 5,
              "S4: Two pages join only exact PC packages, dedupe IDs and count filtered/console/missing products")
        check(snapshot.games.first?.artwork?.url == "https://store-images.s-microsoft.com/image/square",
              "S4: Square BoxArt is preferred and protocol-relative approved art uses the existing validator")
        let requests = await transport.requests
        check(requests.count == 6 && requests.allSatisfy { $0.timeoutInterval == 30 && !$0.httpShouldHandleCookies },
              "S4: Exact bounded request chain uses no cookies or invented endpoint")
        let userBody = try JSONSerialization.jsonObject(with: requests[0].httpBody ?? Data()) as? [String: Any]
        check((userBody?["Properties"] as? [String: String])?["RpsTicket"] == "d=neutral-access"
              && requests[0].value(forHTTPHeaderField: "x-xbl-contract-version") == "1",
              "S4: Xbox user auth uses the observed RPS d= access ticket and contract1")
        let xboxBody = try JSONSerialization.jsonObject(with: requests[1].httpBody ?? Data()) as? [String: Any]
        let storeBody = try JSONSerialization.jsonObject(with: requests[2].httpBody ?? Data()) as? [String: Any]
        check(xboxBody?["RelyingParty"] as? String == "http://xboxlive.com"
              && storeBody?["RelyingParty"] as? String == "http://mp.microsoft.com/",
              "S4: XSTS uses both exact relying parties including Store trailing slash")
        let collectionBody = try JSONSerialization.jsonObject(with: requests[3].httpBody ?? Data()) as? [String: Any]
        let nextBody = try JSONSerialization.jsonObject(with: requests[4].httpBody ?? Data()) as? [String: Any]
        check(collectionBody?["maxPageSize"] as? Int == 100 && collectionBody?["validityType"] as? String == "All"
              && collectionBody?["market"] as? String == "GB" && nextBody?["continuationToken"] as? String == "neutral-next"
              && requests[3].value(forHTTPHeaderField: "Authorization") == "XBL3.0 x=123;neutral-store"
              && requests[3].value(forHTTPHeaderField: "x-xbl-contract-version") == "2",
              "S4: Collections preserves query/page contract, bound account ticket and next continuation")
        let beneficiaries = collectionBody?["beneficiaries"] as? [[String: String]]
        check(beneficiaries?.first == ["identityType": "xuid", "identityValue": "456", "localTicketReference": "xodus"],
              "S4: Collection beneficiary comes only from the matched Xbox identity")
        check(requests[5].value(forHTTPHeaderField: "Authorization") == nil
              && requests[5].url?.host == "displaycatalog.mp.microsoft.com",
              "S4: Private token is never sent with public catalog or image requests")
        let mismatch = PCGamesMockTransport(try authResponses(storeUHS: "999"))
        do {
            _ = try await PCGamesClient(transport: mismatch).library(accessToken: "neutral", market: "US", language: "en-US")
            check(false, "S4: Identity mismatch prevents all collections reads")
        } catch {
            let requestCount = await mismatch.requests.count
            check(error as? PCGamesError == .identityMismatch && requestCount == 3,
                  "S4: Identity mismatch prevents all collections reads")
        }
        check(PCGamesError.xbox(2148916233) == .noXboxProfile
              && PCGamesError.xbox(2148916235) == .regionUnavailable
              && PCGamesError.xbox(2148916238) == .childAccount
              && PCGamesError.xbox(1) == .xboxSignIn,
              "S4: Xbox error codes map to specific safe product guidance")
        let xerr = PCGamesMockTransport([try response(["XErr": 2148916233, "Message": "secret provider text"], status: 401)])
        do {
            _ = try await PCGamesClient(transport: xerr).library(accessToken: "neutral", market: "US", language: "en-US")
            check(false, "S4: XErr is not raw provider text or successful empty Library")
        } catch { check(error as? PCGamesError == .noXboxProfile, "S4: XErr is not raw provider text or successful empty Library") }
        let partial = PCGamesMockTransport(try authResponses() + [page([item(first)], cursor: "next")])
        do {
            _ = try await PCGamesClient(transport: partial).library(accessToken: "neutral", market: "US", language: "en-US")
            check(false, "S4: Failed page never publishes an empty or partial successful Library")
        } catch {
            check(error as? PCGamesError == .incompleteCollection(1),
                  "S4: Failed page never publishes an empty or partial successful Library")
        }
        let repeated = PCGamesMockTransport(try authResponses() + [
            page([item(first)], cursor: "loop"), page([item(first)], cursor: "loop")])
        do {
            _ = try await PCGamesClient(transport: repeated).library(accessToken: "neutral", market: "US", language: "en-US")
            check(false, "S4: Repeated continuation is a failure, not a duplicate loop")
        } catch {
            check(error as? PCGamesError == .incompleteCollection(1), "S4: Repeated continuation is a failure, not a duplicate loop")
        }
        let capped = PCGamesMockTransport(try authResponses() + (0..<20).map { try page([], cursor: "next-\($0)") })
        do {
            _ = try await PCGamesClient(transport: capped).library(accessToken: "neutral", market: "US", language: "en-US")
            check(false, "S4: The complete-page ceiling is exactly20 and continuation cannot become empty success")
        } catch {
            let requestCount = await capped.requests.count
            check(error as? PCGamesError == .incompleteCollection(20) && requestCount == 23,
                  "S4: The complete-page ceiling is exactly20 and continuation cannot become empty success")
        }
        let ids = (0..<21).map { String(format: "FIXTURE%05d", $0) }
        let batches = PCGamesMockTransport(try authResponses() + [
            page(ids.map { item($0) }),
            response(["Products": ids.sorted().prefix(20).map { catalogProduct($0) }]),
            response(["Products": ids.sorted().suffix(1).map { catalogProduct($0) }])])
        let many = try await PCGamesClient(transport: batches).library(accessToken: "neutral", market: "US", language: "en-US")
        let batchRequests = await batches.requests.filter { $0.url?.host == "displaycatalog.mp.microsoft.com" }
        let batchSizes = batchRequests.map { request in
            URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?
                .first(where: { $0.name == "bigIds" })?.value?.split(separator: ",").count
        }
        check(many.games.count == 21 && batchSizes == [20, 1], "S4: Catalog batches never exceed20 exact product IDs")
        let catalogFailure = PCGamesMockTransport(try authResponses() + [page([item(first)])])
        do {
            _ = try await PCGamesClient(transport: catalogFailure).library(accessToken: "neutral", market: "US", language: "en-US")
            check(false, "S4: Catalog failure cannot report a successful empty Library")
        } catch {
            check(error as? PCGamesError == .incompleteCatalog(0), "S4: Catalog failure cannot report a successful empty Library")
        }
        let completeEmpty = PCGamesMockTransport(try authResponses() + [page([])])
        let empty = try await PCGamesClient(transport: completeEmpty).library(accessToken: "neutral", market: "US", language: "en-US")
        let emptyRequestCount = await completeEmpty.requests.count
        check(empty.games.isEmpty && empty.excludedCount == 0 && emptyRequestCount == 4,
              "S4: Only a complete genuinely empty collection supplies an empty Library")
        let unresolved = PCGamesMockTransport(try authResponses() + [page([item("legacy-unresolved-id")])])
        let unresolvedLibrary = try await PCGamesClient(transport: unresolved).library(
            accessToken: "neutral", market: "US", language: "en-US")
        let unresolvedRequests = await unresolved.requests
        check(unresolvedLibrary.games.isEmpty && unresolvedLibrary.excludedCount == 1 && unresolvedRequests.count == 4,
              "S4: Non-catalog Game IDs are counted unresolved; they never enter guessed catalog calls")
        for uri in ["//evil.invalid/image/square", "http://store-images.s-microsoft.com/image/square",
                    "//store-images.s-microsoft.com/image/a?token=secret", "//store-images.s-microsoft.com/image/../file",
                    "//store-images.s-microsoft.com@evil.invalid/image/a"] {
            check(PCGamesClient.artwork(uri: uri, width: 100, height: 100, role: .boxArt) == nil,
                  "S4: Artwork rejects unapproved host/grammar without broadening the shared loader")
        }
        check(PCGamesClient.market(nil) == "US" && PCGamesClient.market("GB") == "GB"
              && PCGamesClient.market("gb&token=x") == "US"
              && PCGamesClient.language("en-GB") == "en-GB"
              && PCGamesClient.language("en-US&token=x") == "en-US",
              "S4: Locale query values are bounded; absent region usesUS")
        let deviceResponse = try response(["device_code": "neutral-device", "user_code": "ABCD-EFGH",
            "verification_uri": "https://www.microsoft.com/link", "expires_in": 900, "interval": 5])
        let tokenResponse = try response(["access_token": "neutral-access", "refresh_token": "neutral-refresh-rotated"])
        let pollingTransport = PCGamesMockTransport([
            deviceResponse, try response(["error": "authorization_pending"], status: 400),
            try response(["error": "slow_down"], status: 400), tokenResponse])
        let sleeper = PCGamesMockSleeper()
        let pollClient = PCGamesClient(transport: pollingTransport, sleep: { await sleeper.sleep($0) })
        let device = try await pollClient.deviceCode()
        let tokens = try await pollClient.poll(device)
        let intervals = await sleeper.intervals
        check(device.userCode == "ABCD-EFGH" && tokens.refresh == "neutral-refresh-rotated"
              && intervals == [.seconds(5), .seconds(5), .seconds(10)],
              "S4: Device-code polling handles pending and adds exactly5sec on slow_down")
        let oauthRequests = await pollingTransport.requests
        check(String(data: oauthRequests[0].httpBody ?? Data(), encoding: .utf8)?.contains(PCGamesClient.clientID) == true
              && oauthRequests.allSatisfy { $0.url?.host == "login.microsoftonline.com" && $0.url?.query == nil },
              "S4: OAuth credentials are form bodies, never argv/URL/query/log payloads")
        for (name, expected) in [("expired_token", PCGamesError.signInExpired), ("authorization_declined", .signInDeclined)] {
            let client = PCGamesClient(transport: PCGamesMockTransport([try response(["error": name], status: 400)]),
                                       sleep: { _ in })
            do { _ = try await client.poll(device); check(false, "S4: Device-code expiry/decline is explicit") }
            catch { check(error as? PCGamesError == expected, "S4: Device-code expiry/decline is explicit") }
        }
        let maliciousDevice = PCGamesMockTransport([try response(["device_code": "neutral", "user_code": "ABCD",
            "verification_uri": "https://evil.invalid/link", "expires_in": 900])])
        do {
            _ = try await PCGamesClient(transport: maliciousDevice).deviceCode()
            check(false, "S4: Browser verification target is an exact Microsoft link")
        } catch { check(error as? PCGamesError == .invalidResponse, "S4: Browser verification target is an exact Microsoft link") }
        let tooBig = PCGamesMockTransport([PCGamesHTTPResponse(status: 200, data: Data(repeating: 0, count: 4 * 1024 * 1024 + 1))])
        do {
            _ = try await PCGamesClient(transport: tooBig).deviceCode()
            check(false, "S4: Mock responses also enforce the4MiB ceiling")
        } catch { check(error as? PCGamesError == .responseTooLarge, "S4: Mock responses also enforce the4MiB ceiling") }
        let saved = PCGamesMockStore("neutral-refresh-old")
        let controllerTransport = PCGamesMockTransport([tokenResponse] + (try authResponses()) + [
            try page([item(first)]), try response(["Products": [catalogProduct(first)]])])
        let controller = PCGamesController(store: saved, client: PCGamesClient(transport: controllerTransport))
        await controller.restorePresence()
        let readsBeforeRefresh = await saved.reads
        let requestsBeforeRefresh = await controllerTransport.requests
        check(controller.hasSavedSignIn && readsBeforeRefresh == 0 && requestsBeforeRefresh.isEmpty,
              "S4: Library entry checks only item presence; it does not read credentials or auto-query")
        controller.refresh()
        await controller.waitForOperation()
        let savedRotations = await saved.saved
        check(controller.snapshot?.games.map(\.id) == [first] && controller.error == nil
              && savedRotations == ["neutral-refresh-rotated"],
              "S4: Only refresh tokens rotate into the mocked Keychain; access/XSTS remain memory-only")
        controller.refresh()
        await controller.waitForOperation()
        check(controller.snapshot?.games.map(\.id) == [first] && controller.error != nil,
              "S4: Refresh failure retains the last complete snapshot with an explicit stale notice")
        await controller.signOut()
        let signedOutToken = await saved.token
        check(!controller.hasSavedSignIn && controller.snapshot == nil && signedOutToken == nil,
              "S4: Sign out removes the one app-owned refresh item and clears the account shelf")
        let deletionStore = PCGamesMockStore("neutral-retained-refresh")
        await deletionStore.refuseDeletion()
        let deletionController = PCGamesController(store: deletionStore, client: PCGamesClient(transport: PCGamesMockTransport([])))
        await deletionController.restorePresence()
        await deletionController.signOut()
        let retainedToken = await deletionStore.token
        check(deletionController.hasSavedSignIn && deletionController.error != nil && retainedToken != nil,
              "S4: Keychain deletion failure is visible and never claims a successful sign out")
        let newStore = PCGamesMockStore()
        let signInTransport = PCGamesMockTransport([deviceResponse, tokenResponse] + (try authResponses()) + [
            try page([item(first)]), try response(["Products": [catalogProduct(first)]])])
        let signing = PCGamesController(store: newStore,
            client: PCGamesClient(transport: signInTransport, sleep: { _ in }))
        signing.signIn()
        signing.signIn()
        await signing.waitForOperation()
        let newRotations = await newStore.saved
        let signInRequestCount = await signInTransport.requests.count
        check(signing.hasSavedSignIn && !signing.sheetPresented && signing.snapshot?.games.count == 1
              && newRotations == ["neutral-refresh-rotated"] && signInRequestCount == 7,
              "S4: One sign-in operation publishes an account-correct complete shelf and ignores duplicate starts")
        let cancelStore = PCGamesMockStore()
        let cancelledTransport = PCGamesMockTransport([deviceResponse, tokenResponse])
        let cancelled = PCGamesController(store: cancelStore,
            client: PCGamesClient(transport: cancelledTransport, sleep: { _ in try await Task.sleep(for: .seconds(60)) }))
        cancelled.signIn()
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while cancelled.deviceCode == nil, cancelled.busy, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(1))
        }
        await cancelled.cancelSignIn()
        let cancelledSaves = await cancelStore.saved
        let cancelledRequestCount = await cancelledTransport.requests.count
        check(!cancelled.busy && !cancelled.sheetPresented && !cancelled.hasSavedSignIn
              && cancelledSaves.isEmpty && cancelledRequestCount == 1,
              "S4: Cancel stops polling and never commits a token or late shelf")
        let revokedStore = PCGamesMockStore("neutral-revoked-refresh")
        let revoked = PCGamesController(store: revokedStore, client: PCGamesClient(transport:
            PCGamesMockTransport([try response(["error": "invalid_grant", "error_description": "secret-shaped text"], status: 400)])))
        await revoked.restorePresence()
        revoked.refresh()
        await revoked.waitForOperation()
        check(revoked.needsSignIn && revoked.snapshot == nil
              && revoked.error == PCGamesError.signInRequired.localizedDescription,
              "S4: Revoked refresh requests fresh sign-in without exposing provider text or pretending empty Library")
        let terminatingStore = PCGamesMockStore()
        let terminating = PCGamesController(store: terminatingStore, client: PCGamesClient(
            transport: PCGamesMockTransport([deviceResponse, tokenResponse]),
            sleep: { _ in try await Task.sleep(for: .seconds(60)) }))
        terminating.signIn()
        terminating.beginTermination()
        await terminating.waitForOperation()
        let terminatingSaves = await terminatingStore.saved
        check(!terminating.busy && !terminating.sheetPresented && terminatingSaves.isEmpty && terminating.snapshot == nil,
              "S4: Normal app termination fences sign-in and discards late personal publication without killing games")
        let imported = InstalledGame(id: UUID(), title: "Different local display name", identityName: "Neutral.Identity",
                                     version: "1.0.0.0", storeId: first, folder: "/neutral", launcher: "/neutral/script",
                                     importedAt: Date())
        check(PCGamesController.installedMatch(snapshot.games[0], in: [imported])?.id == imported.id
              && PCGamesController.installedMatch(PCGame(id: second, title: imported.title, artwork: nil), in: [imported]) == nil,
              "S4: Installed Play matches exact StoreId, never title/history/platform guesses")
    }
}
