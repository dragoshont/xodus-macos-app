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
                    discover: CommandLine.arguments.contains("--probe-discovery"))
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
        check(positive.count == 71, "Pinned producer corpus contains 71 positive frames")
        for (index, frame) in positive.enumerated() {
            do { try validator.validate(frame); check(true, "Producer positive frame \(index + 1)") }
            catch { check(false, "Producer positive frame \(index + 1)") }
        }
        let negative = try fixture("negative").array ?? []
        check(negative.count == 11, "Pinned producer corpus contains eleven negative frames")
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

    func probe(_ configuration: BackendConfiguration, discover: Bool = false) async throws {
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
            let supported: Set<ManagementCommand> = scenario == "discoveryfail"
                ? [.authStatus, .authLogout, .jobs, .discover] : [.authStatus, .authLogout, .jobs]
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
                    if scenario == "discoveryfail", command == "catalog.discover" {
                        guard var response = frames.first(where: {
                            $0["error"]?["details"]?["corpus"]?.string == "pcGamePassDiscovery"
                        })?.object else { exit(3) }
                        response["requestID"] = request["requestID"]
                        try emit(.object(response))
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
        try FileHandle.standardOutput.write(contentsOf: data)
    }
}
