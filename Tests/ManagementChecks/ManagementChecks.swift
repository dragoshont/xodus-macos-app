// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import XodusManagement

@main
enum ManagementChecks {
    static func main() async {
        if CommandLine.arguments.dropFirst().first == "manage" { MockBackend.run() }
        let checks = Checks()
        do {
            if let index = CommandLine.arguments.firstIndex(of: "--probe-backend"),
               CommandLine.arguments.indices.contains(index + 1),
               let stateIndex = CommandLine.arguments.firstIndex(of: "--state-dir"),
               CommandLine.arguments.indices.contains(stateIndex + 1) {
                try await checks.probe(BackendConfiguration(
                    executable: URL(fileURLWithPath: CommandLine.arguments[index + 1]),
                    stateDirectory: URL(fileURLWithPath: CommandLine.arguments[stateIndex + 1])),
                    discover: CommandLine.arguments.contains("--probe-discovery"),
                    query: CommandLine.arguments.contains("--probe-query"))
            } else { try await checks.run() }
        } catch { await checks.check(false, "Check harness: \(safeMessage(error))") }
        exit(await checks.finish() ? 0 : 1)
    }
}

func fixture(_ name: String) throws -> JSONValue {
    guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") else {
        throw ManagementError.invalidPayload
    }
    return try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
}

func safeMessage(_ error: Error) -> String {
    (error as? ManagementError)?.localizedDescription ?? "The fixture check could not complete."
}

actor Checks {
    var count = 0
    var failures = 0

    func check(_ condition: Bool, _ name: String) {
        count += 1
        if condition {
            if !name.hasPrefix("Producer positive frame") { print("PASS: \(name)") }
        }
        else {
            failures += 1
            FileHandle.standardError.write(Data("FAIL: \(name)\n".utf8))
        }
    }

    func finish() -> Bool {
        print("\(count) management checks, \(failures) failures.")
        return failures == 0
    }

    func run() async throws {
        let validator = try ContractValidator()
        let positive = try fixture("positive").array ?? []
        check(positive.count == 77, "Pinned producer corpus contains 77 positive frames")
        for (index, frame) in positive.enumerated() {
            do { try validator.validate(frame); check(true, "Producer positive frame \(index + 1)") }
            catch { check(false, "Producer positive frame \(index + 1)") }
        }
        let negative = try fixture("negative").array ?? []
        check(negative.count == 15, "Pinned producer corpus contains fifteen negative frames")
        for item in negative {
            do {
                guard let frame = item["frame"] else { throw ManagementError.invalidPayload }
                try validator.validate(frame)
                check(false, "Reject \(item["name"]?.string ?? "negative fixture")")
            } catch { check(true, "Reject \(item["name"]?.string ?? "negative fixture")") }
        }
        let flowResults = positive.filter { $0["data"]?["flow"]?.object != nil }
        check(flowResults.count >= 2, "Producer corpus includes native authentication flow results")
        for frame in flowResults {
            guard let data = frame["data"] else { throw ManagementError.invalidPayload }
            let status = try data.decode(AuthenticationStatus.self)
            check(status.flow != nil && !status.entitlementAuthorized,
                  "Typed native authentication flow never promotes PC entitlement")
        }
        let registryResults = positive.filter { $0["data"]?["installations"]?.array != nil }
        check(!registryResults.isEmpty, "Producer corpus includes installed-registry evidence")
        for frame in registryResults {
            guard let data = frame["data"] else { throw ManagementError.invalidPayload }
            let snapshot = try data.decode(InstalledSnapshot.self)
            check(snapshot.scope == "managementRegistryOnly" && snapshot.registryVersion.major == 1,
                  "Typed installed evidence remains explicitly scoped to its management registry")
        }
        guard let discoveryData = positive.first(where: { $0["data"]?["corpus"]?.string == "pcGamePassDiscovery" })?["data"],
              let failedPage = positive.first(where: { $0["error"]?["details"]?["corpus"]?.string == "pcGamePassDiscovery" })?["error"]?["details"] else {
            throw ManagementError.invalidPayload
        }
        let discovery = try discoveryData.decode(CatalogDiscovery.self)
        check(discovery.products.first?.resolvedLanguage == "en" && discovery.failures.count == 1,
              "Typed mixed discovery exposes actual source language and per-product failure")
        try validator.validate(failedPage, definition: "failedDiscoveryData")
        check(try failedPage.decode(CatalogDiscovery.self).products.isEmpty,
              "All-failure details are distinct from success-shaped discovery")
        do {
            try validator.validate(failedPage, definition: "discoveryData")
            check(false, "Empty all-failure page cannot validate as success")
        } catch { check(true, "Empty all-failure page cannot validate as success") }
        guard var pageObject = discoveryData.object,
              var productObject = discoveryData["products"]?.array?.first?.object else {
            throw ManagementError.invalidPayload
        }
        productObject["source"] = .string("syntheticPublicSource")
        pageObject["products"] = .array([.object(productObject)])
        try JSONValue.object(pageObject).decode(CatalogDiscovery.self)
            .validatePublicScope(market: "US", language: "en-US", limit: 8)
        check(true, "Same-base neutral metadata language is explicit and allowed")
        for tag in ["en-GB", "fr"] {
            productObject["resolvedLanguage"] = .string(tag)
            pageObject["products"] = .array([.object(productObject)])
            do {
                try JSONValue.object(pageObject).decode(CatalogDiscovery.self)
                    .validatePublicScope(market: "US", language: "en-US", limit: 8)
                check(false, "Unrelated or other-region language is rejected")
            } catch { check(true, "Unrelated or other-region language is rejected") }
        }
        guard var queryProduct = discoveryData["products"]?.array?.first?.object else {
            throw ManagementError.invalidPayload
        }
        queryProduct["source"] = .string("syntheticPublicSource")
        var queryPage: [String: JSONValue] = [
            "corpus": .string("publicMicrosoftStoreSearch"), "completeness": .string("partial"),
            "source": .string("MicrosoftStoreEdge:v9.0/searchResults"),
            "checkedAt": discoveryData["checkedAt"] ?? .null, "freshness": .string("live"),
            "query": .string("original fixture query"), "products": .array([.object(queryProduct)]),
            "failures": discoveryData["failures"] ?? .array([]), "nextCursor": .null
        ]
        try JSONValue.object(queryPage).decode(CatalogQuery.self).validatePublicScope(
            query: "original fixture query", market: "US", language: "en-US", limit: 8)
        check(true, "Typed network query preserves source, PC scope and mixed failures")
        do {
            try JSONValue.object(queryPage).decode(CatalogQuery.self).validatePublicScope(
                query: "different query", market: "US", language: "en-US", limit: 8)
            check(false, "Network query echo must match its exact request")
        } catch { check(error as? ManagementError == .invalidPayload, "Network query echo must match its exact request") }
        queryPage["products"] = .array([])
        queryPage["failures"] = .array([])
        try JSONValue.object(queryPage).decode(CatalogQuery.self).validatePublicScope(
            query: "original fixture query", market: "US", language: "en-US", limit: 8)
        check(true, "Genuine empty query is distinct from failed product checks")
        queryPage["nextCursor"] = .string("synthetic-opaque-cursor")
        do {
            try JSONValue.object(queryPage).decode(CatalogQuery.self).validatePublicScope(
                query: "original fixture query", market: "US", language: "en-US", limit: 8)
            check(false, "Empty source matches cannot claim another query page")
        } catch { check(error as? ManagementError == .invalidPayload, "Empty source matches cannot claim another query page") }
        let queryResults = positive.compactMap { $0["data"] }.filter {
            $0["corpus"]?.string == "publicMicrosoftStoreSearch"
        }
        check(queryResults.count >= 2, "Pinned query corpus contains real-shape success and empty results")
        for data in queryResults {
            try validator.validate(data, definition: "queryData")
            let page = try data.decode(CatalogQuery.self)
            check(page.corpus == "publicMicrosoftStoreSearch" && page.completeness == "partial",
                  "Typed canonical query remains public and partial, not entitlement")
        }
        guard let failedQuery = positive.first(where: {
            $0["error"]?["details"]?["corpus"]?.string == "publicMicrosoftStoreSearch"
        })?["error"]?["details"] else { throw ManagementError.invalidPayload }
        try validator.validate(failedQuery, definition: "failedQueryData")
        check(try failedQuery.decode(CatalogQuery.self).products.isEmpty,
              "Canonical all-failure query details are strict and independently typed")
        do {
            try validator.validate(failedQuery, definition: "queryData")
            check(false, "All-failure query cannot masquerade as successful empty search")
        } catch { check(true, "All-failure query cannot masquerade as successful empty search") }
        let edges = try fixture("evidence-edge").array ?? []
        check(edges.count == 4, "Four independent evidence edge cases remain distinct")
        for (index, value) in edges.enumerated() {
            do {
                try validator.validate(value, definition: "productEvidence")
                _ = try value.decode(ProductEvidence.self)
                check(true, "Typed evidence edge \(index + 1)")
            } catch { check(false, "Typed evidence edge \(index + 1)") }
        }
        var framer = JSONLineFramer()
        check(try framer.append(Data("{\"kind\"".utf8)).isEmpty, "Split frame is held, not decoded prematurely")
        check(try framer.append(Data(":\"fixture\"}\n".utf8)).count == 1, "Split frame completes in order")
        try framer.finish()
        do {
            var limit = JSONLineFramer()
            _ = try limit.append(Data(repeating: 32, count: JSONLineFramer.maximumBytes + 1))
            check(false, "Oversized frame is rejected")
        } catch { check(error as? ManagementError == .frameTooLarge, "Oversized frame is rejected") }
        do {
            var partial = JSONLineFramer()
            _ = try partial.append(Data("{".utf8))
            try partial.finish()
            check(false, "Truncated frame is rejected on EOF")
        } catch { check(error as? ManagementError == .truncatedFrame, "Truncated frame is rejected on EOF") }
        try activityChecks(positive)

        let client = try ManagementClient()
        let hello = try await client.connect(mockConfiguration("normal"))
        check(hello.supports(.authStatus) && !hello.supports(.launch), "Negotiation gates unsupported gameplay")
        async let auth = client.request(.authStatus)
        async let snapshot = client.request(.jobs)
        let status = try await auth.decode(AuthenticationStatus.self)
        let jobs = try await snapshot.decode(JobsSnapshot.self)
        check(status.state == .signedOut && !status.entitlementAuthorized, "Credentials never imply entitlement")
        check(jobs.jobs.isEmpty, "Concurrent results are correlated by unique request IDs")
        do {
            _ = try await client.request(.launch, params: ["installationID": .string("fixture-install"),
                                                          "expectedRevision": .integer(0)])
            check(false, "Unsupported command is rejected before transport")
        } catch {
            check(error as? ManagementError == .capabilityMissing("game.launch"),
                  "Unsupported command is rejected before transport")
        }
        do {
            _ = try await client.request(.authStatus, params: ["token": .string("synthetic-forbidden-field")])
            check(false, "Credential parameter is rejected before transport")
        } catch { check(error as? ManagementError == .invalidRequest, "Credential parameter is rejected before transport") }
        await client.close()
        let denied = try ManagementClient()
        _ = try await denied.connect(mockConfiguration("keychain"))
        do {
            _ = try await denied.request(.authStatus)
            check(false, "Keychain permission failure is not treated as invalid credentials")
        } catch {
            check(error as? ManagementError == .credentialStoreUnavailable,
                  "Keychain permission failure is not treated as invalid credentials")
        }
        await denied.close()
        check(ManagementCommand.authBegin.defaultTimeout == .seconds(600)
              && ManagementCommand.authLogout.defaultTimeout == .seconds(600)
              && ManagementCommand.authStatus.defaultTimeout == .seconds(30),
              "Human account mutations have a separate finite budget; ordinary reads stay short")
        let human = try ManagementClient()
        _ = try await human.connect(mockConfiguration("humanwait"))
        async let preparing = human.request(.authBegin, params: ["accountScope": .string("default")])
        async let loggingOut = human.request(.authLogout)
        let readStart = ContinuousClock.now
        _ = try await human.request(.jobs)
        check(ContinuousClock.now - readStart < .seconds(2),
              "Public snapshot answers while fake human preparation/logout remain in flight")
        _ = try await preparing.decode(AuthenticationStatus.self)
        _ = try await loggingOut.decode(AuthenticationStatus.self)
        _ = try await human.request(.jobs)
        check(true, "Preparation and logout exceeding thirty seconds preserve the connection")
        await human.close()
        let uncertain = try ManagementClient()
        _ = try await uncertain.connect(mockConfiguration("hangmutation"))
        do {
            _ = try await uncertain.request(.authBegin, params: ["accountScope": .string("default")],
                                            timeout: .milliseconds(200))
            check(false, "Mutation deadline never synthesizes success or blindly retries")
        } catch {
            check(error as? ManagementError == .requestTimedOut,
                  "Mutation deadline never synthesizes success or blindly retries")
        }
        await uncertain.close()
        let reconciled = try ManagementClient()
        _ = try await reconciled.connect(mockConfiguration("normal"))
        let reconciledStatus = try await reconciled.request(.authStatus).decode(AuthenticationStatus.self)
        check(reconciledStatus.state == .signedOut,
              "After an uncertain mutation, reconnect reads authoritative status before another mutation")
        await reconciled.close()
        let discoveryFailure = try ManagementClient()
        _ = try await discoveryFailure.connect(mockConfiguration("discoveryfail"))
        do {
            _ = try await discoveryFailure.request(.discover, params: [
                "market": .string("US"), "language": .string("en-US"), "limit": .integer(8), "cursor": .null
            ])
            check(false, "Transport preserves only schema-validated all-failure discovery details")
        } catch let error as ManagementError {
            if case .discoveryFailed(let page) = error {
                check(page.products.isEmpty && !page.failures.isEmpty,
                      "Transport preserves only schema-validated all-failure discovery details")
            } else { check(false, "Transport preserves only schema-validated all-failure discovery details") }
        }
        await discoveryFailure.close()
        for scenario in ["queryfail", "badqueryfail"] {
            let queryFailure = try ManagementClient()
            _ = try await queryFailure.connect(mockConfiguration(scenario))
            do {
                _ = try await queryFailure.request(.query, params: [
                    "query": .string("original fixture query"), "market": .string("US"),
                    "language": .string("en-US"), "limit": .integer(8), "cursor": .null
                ])
                check(false, "Query failure transport \(scenario)")
            } catch let error as ManagementError {
                if scenario == "queryfail", case .queryFailed(let page) = error {
                    check(page.products.isEmpty && !page.failures.isEmpty,
                          "Transport preserves schema-validated failed query details only")
                } else {
                    check(scenario == "badqueryfail" && error == .invalidPayload,
                          "Transport rejects malformed all-failure query details")
                }
            }
            await queryFailure.close()
        }
        for scenario in ["prompt", "oversize", "partial", "mismatch", "wrongid", "wrongshape", "eof", "exit", "timeout"] {
            let bad = try ManagementClient()
            do {
                _ = try await bad.connect(mockConfiguration(scenario))
                _ = try await bad.request(.authStatus, timeout: .milliseconds(200))
                check(false, "Transport rejects \(scenario)")
            } catch { check(error is ManagementError, "Transport rejects \(scenario) without raw diagnostic text") }
            await bad.close()
        }
    }

    func probe(_ configuration: BackendConfiguration, discover: Bool = false, query: Bool = false) async throws {
        let client = try ManagementClient()
        do {
            let hello = try await client.connect(configuration)
            check(hello.schema == "urn:xodus:management:1.0", "Actual Xodus hello/schema negotiation")
            check(!hello.supports(.launch) && !hello.supports(.plan),
                  "Uncertified runtime/packages remain capability-gated")
            if hello.supports(.authStatus) {
                do {
                    let status = try await client.request(.authStatus).decode(AuthenticationStatus.self)
                    check(status.credentialStore == "macOSKeychain" && !status.entitlementAuthorized,
                          "Actual native Keychain status is not ownership proof")
                } catch let error as ManagementError {
                    switch error {
                    case .backendError("AUTH_INVALID", _):
                        check(true, "Actual auth.status explicitly rejects invalid saved credentials; no valid sign-in claimed")
                    case .credentialStoreUnavailable:
                        check(true, "Actual auth.status reports inaccessible credential store; no permission or account assumed")
                    default: throw error
                    }
                }
            }
            if hello.supports(.search) {
                let search = try await client.request(.search, params: [
                    "query": .string(""), "market": .string("US"), "language": .string("en-US"),
                    "platform": .string("pc"), "limit": .integer(100), "cursor": .null
                ]).decode(CatalogSearch.self)
                check(search.corpus == "observedPublicProducts" && search.completeness == "partial",
                      "Actual catalog is explicitly partial, not an entitled library")
            }
            if hello.supports(.jobs) {
                let snapshot = try await client.request(.jobs).decode(JobsSnapshot.self)
                check(snapshot.sessionID == hello.sessionID,
                      "Actual activity snapshot belongs to the negotiated engine session")
                var activity = ActivityStore()
                try activity.apply(snapshot)
                check(!activity.needsSnapshot, "Actual authoritative durable activity snapshot")
            }
            if query {
                guard hello.supports(.query) else { throw ManagementError.capabilityMissing("catalog.query") }
                let params: [String: JSONValue] = [
                    "query": .string("Halo"), "market": .string("US"), "language": .string("en-US"),
                    "limit": .integer(8), "cursor": .null
                ]
                func queryPage(_ params: [String: JSONValue]) async throws -> CatalogQuery {
                    do {
                        return try await client.request(.query, params: params, timeout: .seconds(45))
                            .decode(CatalogQuery.self)
                    } catch ManagementError.queryFailed(let page) { return page }
                }
                let first = try await queryPage(params)
                try first.validatePublicScope(query: "Halo", market: "US", language: "en-US", limit: 8)
                check(!first.products.isEmpty, "Actual Store network query resolves source-backed PC candidates")
                if let cursor = first.nextCursor {
                    var next = params
                    next["cursor"] = .string(cursor)
                    let second = try await queryPage(next)
                    try second.validatePublicScope(query: "Halo", market: "US", language: "en-US", limit: 8)
                    let firstIDs = Set(first.products.map(\.id) + first.failures.map(\.id))
                    let secondIDs = Set(second.products.map(\.id) + second.failures.map(\.id))
                    check(!secondIDs.isEmpty && firstIDs.isDisjoint(with: secondIDs)
                          && second.nextCursor != cursor,
                          "Actual scoped Store cursor advances without merging edition/product identities")
                }
                let emptyQuery = "XodusNoMatch9F4A12C7"
                var emptyParams = params
                emptyParams["query"] = .string(emptyQuery)
                let empty = try await client.request(.query, params: emptyParams, timeout: .seconds(45))
                    .decode(CatalogQuery.self)
                try empty.validatePublicScope(query: emptyQuery, market: "US", language: "en-US", limit: 8)
                check(empty.products.isEmpty && empty.failures.isEmpty && empty.nextCursor == nil,
                      "Actual zero-source query returns genuine empty success, not metadata failure")
                _ = try await client.request(.jobs).decode(JobsSnapshot.self)
                check(true, "Actual connection survives a genuine zero-source Store query")
            }
            if hello.supports(.installed) {
                let registry = try await client.request(.installed).decode(InstalledSnapshot.self)
                check(registry.scope == "managementRegistryOnly"
                      && Set(registry.installations.map(\.id)).count == registry.installations.count,
                      "Actual registry does not import legacy game folders")
            }
            if hello.supports(.diagnostics) {
                let report = try await client.request(.diagnostics)
                check(report["redacted"] == .bool(true), "Actual diagnostic preview is explicitly redacted")
            }
            if discover {
                guard hello.supports(.discover) else { throw ManagementError.capabilityMissing("catalog.discover") }
                let first = try await client.request(.discover, params: [
                    "market": .string("US"), "language": .string("en-US"), "limit": .integer(2), "cursor": .null
                ], timeout: .seconds(45)).decode(CatalogDiscovery.self)
                try first.validatePublicScope(market: "US", language: "en-US", limit: 2)
                check(!first.products.isEmpty, "Actual source-backed PC discovery is partial and entitlement remains unknown")
                guard let cursor = first.nextCursor else { throw ManagementError.invalidPayload }
                let second = try await client.request(.discover, params: [
                    "market": .string("US"), "language": .string("en-US"), "limit": .integer(2), "cursor": .string(cursor)
                ], timeout: .seconds(45)).decode(CatalogDiscovery.self)
                try second.validatePublicScope(market: "US", language: "en-US", limit: 2)
                check(second.corpusRevision == first.corpusRevision
                      && Set(first.products.map(\.id) + first.failures.map(\.id))
                        .isDisjoint(with: Set(second.products.map(\.id) + second.failures.map(\.id))),
                      "Actual discovery cursor advances with stable provenance and distinct identities")
                guard let product = first.products.first else { throw ManagementError.invalidPayload }
                let searched = try await client.request(.search, params: [
                    "query": .string(product.title), "market": .string("US"), "language": .string("en-US"),
                    "platform": .string("pc"), "limit": .integer(100), "cursor": .null
                ]).decode(CatalogSearch.self)
                check(searched.products.contains { $0.id == product.id },
                      "Actual checked-catalog title search resolves a source-backed discovered product")
            }
            await client.close()
        } catch {
            await client.close()
            throw error
        }
    }

    func activityChecks(_ positive: [JSONValue]) throws {
        guard let fixtureEvent = positive.first(where: { $0["kind"]?.string == "event" }),
              var event = fixtureEvent.object, var job = fixtureEvent["data"]?.object else {
            throw ManagementError.invalidPayload
        }
        let session = fixtureEvent["sessionID"] ?? .string("fixture-session")
        let cancelledJob = JSONValue.object(job)
        job["state"] = .string("running")
        job["revision"] = .integer(1)
        job["error"] = .null
        let snapshot = try JSONValue.object(["sessionID": session, "watermark": .integer(1),
                                             "jobs": .array([.object(job)])]).decode(JobsSnapshot.self)
        var activity = ActivityStore()
        try activity.apply(snapshot)
        event["sequence"] = .integer(2)
        event["revision"] = .integer(2)
        var terminal = cancelledJob.object ?? [:]
        terminal["revision"] = .integer(2)
        event["data"] = .object(terminal)
        let value = try JSONValue.object(event).decode(ManagementEvent.self)
        try activity.beginSnapshot()
        try activity.apply(value)
        check(activity.watermark == 1 && activity.isReconciling, "Live event is fenced during snapshot request")
        try activity.apply(snapshot)
        check(activity.watermark == 2 && !activity.isReconciling,
              "Snapshot applies before buffered events above its watermark")
        try activity.apply(value)
        check(activity.jobs.first?.state == .cancelled && activity.watermark == 2, "Contiguous event updates activity")
        try activity.apply(value)
        check(activity.jobs.count == 1 && activity.watermark == 2, "Duplicate replay event is idempotent")
        event["sequence"] = .integer(4)
        try activity.apply(JSONValue.object(event).decode(ManagementEvent.self))
        check(activity.needsSnapshot && activity.watermark == 2, "Sequence gap requires authoritative snapshot")
        do {
            try activity.apply(snapshot)
            check(false, "Regressive snapshot watermark is rejected")
        } catch { check(true, "Regressive snapshot watermark is rejected") }
        activity = ActivityStore()
        try activity.apply(snapshot)
        event["sessionID"] = .string("fixture-new-session")
        try activity.apply(JSONValue.object(event).decode(ManagementEvent.self))
        check(activity.needsSnapshot, "Changed session requires authoritative snapshot")
        var duplicate = try snapshot.jobs.map { try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode($0)) }
        duplicate += duplicate
        do {
            let invalid = try JSONValue.object(["sessionID": session, "watermark": .integer(2),
                                                "jobs": .array(duplicate)]).decode(JobsSnapshot.self)
            try activity.apply(invalid)
            check(false, "Duplicate installation/activity identities fail closed")
        } catch { check(true, "Duplicate installation/activity identities fail closed") }
    }

    func mockConfiguration(_ scenario: String) -> BackendConfiguration {
        BackendConfiguration(executable: URL(fileURLWithPath: CommandLine.arguments[0]),
            stateDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent("XodusManagementChecks-\(UUID().uuidString)")
                .appendingPathComponent(scenario))
    }
}

enum MockBackend {
    static func run() -> Never {
        guard let index = CommandLine.arguments.firstIndex(of: "--state-dir"),
              CommandLine.arguments.indices.contains(index + 1) else { exit(2) }
        let scenario = URL(fileURLWithPath: CommandLine.arguments[index + 1]).lastPathComponent
        do {
            let frames = try fixture("positive").array ?? []
            var hello = frames.first(where: { $0["data"]?["schema"] != nil })?["data"]?.object ?? [:]
            var supported: Set<ManagementCommand> = [.authStatus, .authLogout, .jobs]
            if ["discoveryfail", "discoveryrecover"].contains(scenario) { supported.insert(.discover) }
            if ["queryfail", "badqueryfail", "queryempty", "queryslow"].contains(scenario) { supported.insert(.query) }
            if ["expired", "expiredpermission", "transientauth", "latecancel", "humanwait", "hangmutation", "beginfail"].contains(scenario) {
                supported.formUnion([.authBegin, .authCancel])
            }
            var loggedOut = false, flowStarted = false, cancelledLate = false
            var flowReads = 0, discoveryReads = 0, profileReads = 0
            hello["capabilities"] = .array(ManagementCommand.allCases.map { command in .object([
                "command": .string(command.rawValue), "supported": .bool(supported.contains(command)),
                "audience": .null, "reason": supported.contains(command) ? .null : .string("Fixture gate.")
            ]) })
            while let line = readLine() {
                let request = try JSONDecoder().decode(JSONValue.self, from: Data(line.utf8))
                let command = request["command"]?.string ?? ""
                if command == "hello" {
                    if scenario == "prompt" { print("Synthetic interactive prompt"); fflush(stdout); continue }
                    if scenario == "oversize" { print(String(repeating: "x", count: JSONLineFramer.maximumBytes + 1)); fflush(stdout); continue }
                    if scenario == "partial" { FileHandle.standardOutput.write(Data("{\"kind\":".utf8)); exit(0) }
                    var result = result(request, data: .object(hello))
                    if scenario == "mismatch" { result["protocol"] = .object(["major": .integer(2), "minor": .integer(0)]) }
                    try emit(.object(result))
                } else {
                    if scenario == "beginfail", command == "auth.begin" {
                        try emitFailure(request, code: "AUTH_INVALID")
                        continue
                    }
                    if ["expired", "expiredpermission", "transientauth", "latecancel"].contains(scenario) {
                        if command == "auth.begin" { flowStarted = true; flowReads = 0 }
                        if command == "auth.logout" { loggedOut = true; flowStarted = false }
                        if command == "auth.cancel", scenario == "latecancel" {
                            cancelledLate = true
                            try emitFailure(request, code: "INVALID_TRANSITION")
                            continue
                        }
                        if command.hasPrefix("auth.") {
                            if command == "auth.status", scenario == "expiredpermission" {
                                profileReads += 1
                                if profileReads == 2 {
                                    try emitFailure(request, code: "AUTH_INVALID", category: "credentialStoreUnavailable")
                                    continue
                                }
                            }
                            if command == "auth.status", flowStarted {
                                flowReads += 1
                                if scenario == "transientauth", flowReads == 1 {
                                    try emitFailure(request, code: "AUTH_INVALID", category: "credentialStoreUnavailable")
                                    continue
                                }
                            }
                            let completed = flowStarted && command == "auth.status"
                                && (scenario != "latecancel" || cancelledLate)
                            var status: [String: JSONValue] = [
                                "state": .string(completed ? "credentialPresent"
                                    : ["expired", "expiredpermission"].contains(scenario) && !loggedOut && !flowStarted
                                        ? "expired" : "signedOut"),
                                "credentialStore": .string("macOSKeychain"), "audience": .null,
                                "expiresAt": .null, "entitlementAuthorized": .bool(false)
                            ]
                            if flowStarted {
                                status["flow"] = .object(["flowID": .string("fixture-native-flow"),
                                    "state": .string(completed ? "completed" : "pending"), "error": .null])
                            }
                            try emit(.object(result(request, data: .object(status))))
                            continue
                        }
                    }
                    if ["humanwait", "hangmutation"].contains(scenario),
                       ["auth.begin", "auth.logout"].contains(command) {
                        if scenario == "humanwait" {
                            let response = result(request, data: .object([
                                "state": .string("signedOut"), "credentialStore": .string("macOSKeychain"),
                                "audience": .null, "expiresAt": .null, "entitlementAuthorized": .bool(false)
                            ]))
                            DispatchQueue.global().async {
                                Thread.sleep(forTimeInterval: 31)
                                do { try emit(.object(response)) }
                                catch { exit(3) }
                            }
                        }
                        continue
                    }
                    if scenario == "discoveryrecover", command == "catalog.discover" {
                        discoveryReads += 1
                        guard let failedPage = frames.first(where: {
                            $0["error"]?["details"]?["corpus"]?.string == "pcGamePassDiscovery"
                        }) else { exit(3) }
                        if discoveryReads == 1 {
                            guard var response = failedPage.object else { exit(3) }
                            response["requestID"] = request["requestID"]
                            try emit(.object(response))
                        } else {
                            guard var page = frames.first(where: {
                                $0["data"]?["corpus"]?.string == "pcGamePassDiscovery"
                            })?["data"]?.object else { exit(3) }
                            page["products"] = .array((page["products"]?.array ?? []).map { product in
                                var value = product.object ?? [:]
                                value["source"] = .string("syntheticPublicSource")
                                return .object(value)
                            })
                            page["failures"] = .array([])
                            page["corpusRevision"] = failedPage["error"]?["details"]?["corpusRevision"]
                            page["nextCursor"] = .null
                            try emit(.object(result(request, data: .object(page))))
                        }
                        continue
                    }
                    if scenario == "discoveryfail", command == "catalog.discover" {
                        guard var response = frames.first(where: {
                            $0["error"]?["details"]?["corpus"]?.string == "pcGamePassDiscovery"
                        })?.object else { exit(3) }
                        response["requestID"] = request["requestID"]
                        try emit(.object(response))
                        continue
                    }
                    if ["queryfail", "badqueryfail"].contains(scenario), command == "catalog.query" {
                        guard var response = frames.first(where: {
                            $0["error"]?["details"]?["corpus"]?.string == "publicMicrosoftStoreSearch"
                        })?.object else { exit(3) }
                        response["requestID"] = request["requestID"]
                        if scenario == "badqueryfail" {
                            guard var error = response["error"]?.object,
                                  var details = error["details"]?.object else { exit(3) }
                            details["failures"] = .array([])
                            error["details"] = .object(details)
                            response["error"] = .object(error)
                        }
                        try emit(.object(response))
                        continue
                    }
                    if ["queryempty", "queryslow"].contains(scenario), command == "catalog.query" {
                        guard var page = frames.first(where: {
                            $0["data"]?["corpus"]?.string == "publicMicrosoftStoreSearch"
                                && $0["data"]?["products"]?.array?.isEmpty == true
                        })?["data"]?.object else { exit(3) }
                        page["query"] = request["params"]?["query"]
                        if scenario == "queryslow" { Thread.sleep(forTimeInterval: 1) }
                        try emit(.object(result(request, data: .object(page))))
                        continue
                    }
                    if scenario == "eof" { exit(0) }
                    if scenario == "exit" { exit(7) }
                    if scenario == "timeout" { Thread.sleep(forTimeInterval: 5); continue }
                    let data: JSONValue
                    if command == "jobs.snapshot" {
                        data = .object(["sessionID": .string("fixture-session"), "watermark": .integer(0), "jobs": .array([])])
                    } else {
                        data = .object(["state": .string("signedOut"), "credentialStore": .string("macOSKeychain"),
                            "audience": .null, "expiresAt": .null, "entitlementAuthorized": .bool(false)])
                    }
                    var response = result(request, data: scenario == "wrongshape" ? .object(hello) : data)
                    if scenario == "keychain" {
                        response.removeValue(forKey: "data")
                        response["ok"] = .bool(false)
                        response["error"] = .object([
                            "code": .string("AUTH_INVALID"), "message": .string("Synthetic store failure."),
                            "retryable": .bool(false),
                            "details": .object(["category": .string("credentialStoreUnavailable")])
                        ])
                    }
                    if scenario == "wrongid" { response["requestID"] = .string("fixture-unexpected") }
                    try emit(.object(response))
                }
            }
            exit(0)
        } catch { exit(3) }
    }

    static func result(_ request: JSONValue, data: JSONValue) -> [String: JSONValue] {
        ["kind": .string("result"), "protocol": .object(["major": .integer(1), "minor": .integer(0)]),
         "requestID": request["requestID"] ?? .string("fixture-invalid"), "ok": .bool(true), "data": data]
    }

    static func emit(_ frame: JSONValue) throws {
        var data = try JSONEncoder().encode(frame)
        data.append(10)
        outputLock.lock()
        defer { outputLock.unlock() }
        try FileHandle.standardOutput.write(contentsOf: data)
    }

    private static let outputLock = NSLock()

    static func emitFailure(_ request: JSONValue, code: String, category: String? = nil) throws {
        var error: [String: JSONValue] = [
            "code": .string(code), "message": .string("Synthetic fixture failure."), "retryable": .bool(false)
        ]
        if let category { error["details"] = .object(["category": .string(category)]) }
        try emit(.object([
            "kind": .string("result"), "protocol": .object(["major": .integer(1), "minor": .integer(0)]),
            "requestID": request["requestID"] ?? .null, "ok": .bool(false), "error": .object(error)
        ]))
    }
}
