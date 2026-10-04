// SPDX-License-Identifier: GPL-3.0-only
import CoreFoundation
import Foundation
import XodusManagement

@MainActor
enum NativeChecks {
    static func launch() -> Never {
        Task { exit(await run() ? 0 : 1) }
        CFRunLoopRun()
        fatalError("The native check run loop ended before completion.")
    }

    static func run() async -> Bool {
        var count = 0, failures = 0
        func check(_ condition: Bool, _ name: String) {
            count += 1
            if condition { print("PASS: \(name)") }
            else {
                failures += 1
                FileHandle.standardError.write(Data("FAIL: \(name)\n".utf8))
            }
            fflush(stdout)
        }
        func configuration(_ scenario: String) -> BackendConfiguration {
            let executable = URL(fileURLWithPath: CommandLine.arguments[0])
                .deletingLastPathComponent().appendingPathComponent("XodusManagementChecks")
            let state = FileManager.default.temporaryDirectory
                .appendingPathComponent("XodusNativeChecks-\(UUID().uuidString)").appendingPathComponent(scenario)
            return BackendConfiguration(executable: executable, stateDirectory: state)
        }
        func session(_ scenario: String) -> LiveSession { LiveSession(configuration: configuration(scenario)) }
        func trace(_ configuration: BackendConfiguration) throws -> [String] {
            try String(contentsOf: configuration.stateDirectory.appendingPathComponent("lifecycle.log"),
                       encoding: .utf8).split(separator: "\n").map(String.init)
        }
        func cleanLifecycle(_ configuration: BackendConfiguration) throws {
            try FileManager.default.removeItem(at: configuration.stateDirectory.deletingLastPathComponent())
        }
        func waitForTrace(_ marker: String, _ configuration: BackendConfiguration) async throws {
            let deadline = ContinuousClock.now.advanced(by: .seconds(5))
            while true {
                if FileManager.default.fileExists(atPath: configuration.stateDirectory.appendingPathComponent("lifecycle.log").path),
                   try trace(configuration).contains(marker) { return }
                guard ContinuousClock.now < deadline else { throw ManagementError.requestTimedOut }
                try await Task.sleep(for: .milliseconds(20))
            }
        }
        do {
            let expired = session("expired")
            await expired.connect()
            check(expired.isReady && !expired.canSignIn, "Unchecked account cannot blindly retry a mutation")
            await expired.refreshAccount()
            check(expired.authentication?.state == .expired && expired.needsAccountDisconnect
                  && expired.canDisconnectAccount && !expired.canSignIn,
                  "Expired profile exposes confirmed disconnect recovery, not rejected sign-in")
            await expired.signOut()
            check(expired.authentication?.state == .signedOut && expired.canSignIn,
                  "Confirmed launcher logout establishes signed-out state before sign-in")
            await expired.beginSignIn()
            try await wait { expired.authentication?.flow?.state == .completed }
            check(expired.authentication?.state == .credentialPresent && !expired.signInPending,
                  "Expired-profile recovery completes through actual mocked native session requests")
            await expired.disconnect()

            let denied = session("expiredpermission")
            await denied.connect()
            await denied.refreshAccount()
            await denied.refreshAccount()
            check(denied.authentication?.state == .expired && !denied.canDisconnectAccount,
                  "An inaccessible-store error disables disconnect of an earlier expired snapshot")
            await denied.signOut()
            await denied.refreshAccount()
            check(denied.authentication?.state == .expired,
                  "Unavailable-store recovery preserves the existing profile without a deletion request")
            await denied.disconnect()

            let uncertain = session("beginfail")
            await uncertain.connect()
            await uncertain.refreshAccount()
            await uncertain.beginSignIn()
            check(!uncertain.accountStatusCurrent && !uncertain.canSignIn,
                  "Failed sign-in preparation invalidates pre-mutation status before another attempt")
            let preparationSummary = uncertain.errorMessage ?? ""
            check(preparationSummary.hasPrefix("Microsoft sign-in could not start.")
                  && preparationSummary.contains("AUTH_INVALID") && preparationSummary.contains("Stage: stageUnavailable")
                  && !preparationSummary.contains("disconnect") && !preparationSummary.contains("saved sign-in")
                  && !preparationSummary.contains("Original preparation upstream sentinel"),
                  "Request-level sign-in failure never implies invalid saved credentials or deletion advice")
            await uncertain.refreshAccount()
            check(uncertain.accountStatusCurrent && uncertain.canSignIn,
                  "A fresh status read is required to recover from failed sign-in preparation")
            await uncertain.disconnect()

            for scenario in ["failedflow", "failedflownocode"] {
                let failed = session(scenario)
                await failed.connect()
                await failed.refreshAccount()
                await failed.beginSignIn()
                let summary = failed.accountFailureSummary ?? ""
                check(failed.authentication?.flow?.state == .failed && failed.isReady && !failed.signInPending
                      && !summary.isEmpty && !summary.contains("Original synthetic upstream wording")
                      && !summary.contains("disconnect") && !summary.contains("saved sign-in"),
                      "Failed auth flow surfaces a local safe reason without raw upstream message or success")
                check(scenario == "failedflow" ? summary.contains("AUTH_INVALID")
                      : summary.contains("Failure stage is unavailable") && !summary.contains("AUTH_INVALID"),
                      "Auth summary preserves the validated failure code and never invents a missing cause")
                await failed.disconnect()
            }

            for diagnostic in NativeConsentFailure.allCases {
                let failed = session("failedstage-\(diagnostic.rawValue)")
                await failed.connect()
                await failed.refreshAccount()
                await failed.beginSignIn()
                let summary = failed.accountFailureSummary ?? ""
                check(failed.authentication?.flow?.error?.nativeConsentFailure == diagnostic
                      && summary.contains("Stage: \(diagnostic.stage)") && summary.contains("Reason: \(diagnostic.rawValue)")
                      && !summary.contains("Original synthetic upstream wording") && failed.isReady
                      && failed.authentication?.entitlementAuthorized == false && !failed.signInPending
                      && (diagnostic.stage != "devicePreparation"
                          || failed.accountFailureTitle == "Microsoft sign-in could not start."),
                      "Known closed auth stage/reason is locally mapped without upstream text or entitlement promotion")
                if diagnostic == .pipelineFailed {
                    check(summary.contains("does not establish that a browser appeared or consent completed"),
                          "Native pipeline diagnostic never invents observed Microsoft UI or successful consent")
                }
                if diagnostic == .providerProofInvalid {
                    check(summary.contains("did not provide a valid sign-in proof")
                          && !summary.contains("cryptograph") && !summary.contains("signature")
                          && !summary.contains("disconnect") && !summary.contains("delete"),
                          "Device-proof shape or missing-proof failure never invents a cryptographic cause or credential deletion")
                }
                let subsiteCopy: String?
                switch diagnostic {
                case .tokenKindInvalid:
                    subsiteCopy = "The device sign-in token uses a format this launcher cannot accept."
                case .tokenAudienceInvalid:
                    subsiteCopy = "The device sign-in token did not match the required context."
                case .tokenCipherInvalid:
                    subsiteCopy = "The device sign-in token payload could not be processed."
                case .tokenSecretInvalid:
                    subsiteCopy = "The device sign-in proof was missing or invalid."
                default:
                    subsiteCopy = nil
                }
                if let subsiteCopy {
                    check(summary.contains(subsiteCopy) && failed.accountFailureTitle == "Microsoft sign-in could not start."
                          && !summary.contains("cryptograph") && !summary.contains("signature")
                          && !summary.contains("Microsoft rejected") && !summary.contains("disconnect")
                          && !summary.contains("delete") && !summary.contains("4096")
                          && !summary.contains("version4") && !summary.contains("base64") && !summary.contains("STS"),
                          "Static token subsite copy reports only the agreed guard category, not values or a guessed cause")
                }
                await failed.disconnect()
            }
            for diagnostic in [NativeConsentFailure.tokenKindInvalid, .tokenAudienceInvalid,
                               .tokenCipherInvalid, .tokenSecretInvalid] {
                for suffix in ["extra", "unknown", "mismatched", "cancelcode", "expirycode", "internalcode"] {
                    let failed = session("failedstage-\(diagnostic.rawValue)-\(suffix)")
                    await failed.connect()
                    await failed.refreshAccount()
                    await failed.beginSignIn()
                    let summary = failed.accountFailureSummary ?? ""
                    check(failed.isReady && failed.authentication?.flow?.error?.nativeConsentFailure == nil
                          && failed.authentication?.entitlementAuthorized == false && !failed.signInPending
                          && summary.contains("Stage: stageUnavailable") && !summary.contains("Reason:")
                          && !summary.contains("Original extra-field sentinel")
                          && !summary.contains("Original synthetic upstream wording")
                          && failed.accountFailureTitle != "Microsoft sign-in could not start.",
                          "Actual mock-child subsite rejects extra/unknown/stage/non-AUTH details without secret retention or guessed preparation")
                    await failed.disconnect()
                }
            }
            for suffix in ["extra", "unknown", "mismatched", "cancelcode", "expirycode"] {
                let failed = session("failedstage-\(suffix)")
                await failed.connect()
                await failed.refreshAccount()
                await failed.beginSignIn()
                let summary = failed.accountFailureSummary ?? ""
                check(failed.isReady && failed.authentication?.flow?.error?.nativeConsentFailure == nil
                      && summary.contains("Stage: stageUnavailable") && !summary.contains("Reason:")
                      && !summary.contains("Original extra-field sentinel") && !summary.contains("Original synthetic upstream wording"),
                      "Malformed/extra/unknown/incompatible diagnostics yield honest unavailable stage without secret sentinel")
                await failed.disconnect()
            }
            let gateConfiguration = configuration("authgate")
            let gated = LiveSession(configuration: gateConfiguration)
            await gated.connect()
            await gated.refreshAccount()
            let beginning = Task { await gated.beginSignIn() }
            try await wait { gated.accountBusy }
            await gated.beginSignIn()
            await beginning.value
            await gated.beginSignIn()
            check(try gated.signInPending && !gated.canSignIn && gated.accountFailureSummary == nil
                  && trace(gateConfiguration).filter { $0 == "auth.begin" }.count == 1,
                  "Busy and pending state reject duplicate native sign-in activation before any second mutation")
            let cancelling = Task { await gated.cancelSignIn() }
            try await wait { gated.accountBusy }
            await gated.cancelSignIn()
            await cancelling.value
            check(try gated.authentication?.flow?.state == .cancelled && !gated.signInPending
                  && gated.accountFailureSummary == nil
                  && trace(gateConfiguration).filter { $0 == "auth.cancel" }.count == 1,
                  "Busy cancellation gate sends one request and does not invent failure-stage diagnostics")
            await gated.disconnect()
            try cleanLifecycle(gateConfiguration)

            let unavailable = session("transientauth")
            await unavailable.connect()
            await unavailable.refreshAccount()
            await unavailable.beginSignIn()
            try await wait { !unavailable.accountStatusCurrent && unavailable.signInPending }
            check(!unavailable.canSignIn && !unavailable.canDisconnectAccount,
                  "Transient inaccessible store never permits deletion or new sign-in")
            try await wait { unavailable.authentication?.flow?.state == .completed }
            check(unavailable.isReady && unavailable.authentication?.state == .credentialPresent,
                  "Pending sign-in reconciles after one credential-store-unavailable result")
            await unavailable.disconnect()

            let committing = session("latecancel")
            await committing.connect()
            await committing.refreshAccount()
            await committing.beginSignIn()
            await committing.refreshAccount()
            check(committing.signInPending, "Safe status remains usable while a sign-in is pending")
            await committing.cancelSignIn()
            check(committing.signInPending && committing.authentication?.flow?.state != .cancelled,
                  "Rejected commit cancellation never reports false cancellation")
            try await wait { committing.authentication?.flow?.state == .completed }
            check(committing.authentication?.state == .credentialPresent && committing.isReady,
                  "Late INVALID_TRANSITION cancellation resumes reconciliation to completion")
            await committing.disconnect()

            let discovery = session("discoveryrecover")
            await discovery.connect()
            await discovery.refreshCatalog("")
            let failedIDs = Set(discovery.discoveryFailures.map(\.id))
            check(discovery.products.isEmpty && !failedIDs.isEmpty && discovery.canLoadMoreCatalog
                  && discovery.catalogError != nil,
                  "All-failure initial page exposes valid continuation without hiding failures")
            await discovery.refreshCatalog("", more: true)
            check(!discovery.products.isEmpty && Set(discovery.discoveryFailures.map(\.id)) == failedIDs
                  && discovery.products.flatMap(\.editions).allSatisfy { $0.entitlement.kind == .unknown },
                  "Successful continuation retains earlier failures without ownership promotion")
            await discovery.disconnect()

            let empty = session("queryempty")
            await empty.connect()
            await empty.refreshCatalog("XodusNoMatch9F4A12C7")
            check(empty.isReady && empty.products.isEmpty && empty.discoveryFailures.isEmpty
                  && empty.catalogError == nil && empty.catalogCorpus == "publicMicrosoftStoreSearch"
                  && empty.nextCursor == nil && empty.discoveryCheckedAt != nil,
                  "Genuine empty query remains live, scoped and distinct from all-failure pages")
            await empty.refreshAccount()
            check(empty.isReady && empty.accountStatusCurrent,
                  "Native status reconciliation still works after a genuine empty query")
            await empty.disconnect()

            let stopped = session("queryslow")
            await stopped.connect()
            let late = Task { await stopped.refreshCatalog("XodusNoMatch9F4A12C7") }
            try await wait { stopped.searching }
            stopped.stopCatalogSearch()
            await late.value
            check(stopped.isReady && stopped.catalogStopped && stopped.discoveryCheckedAt == nil,
                  "Stopped search discards later bounded results without pretending HTTP was cancelled")
            await stopped.disconnect()

            let sourceFailure = session("querynodetails")
            await sourceFailure.connect()
            await sourceFailure.refreshCatalog("Original source query")
            check(sourceFailure.isReady && sourceFailure.catalogError != nil,
                  "Source-level PACKAGE_UNAVAILABLE without batch details is a recoverable catalog error")
            try await sourceFailure.reconcileActivity()
            check(sourceFailure.isReady && !sourceFailure.activity.needsSnapshot,
                  "Native snapshot still succeeds on the same connection after a source-level query error")
            await sourceFailure.disconnect()

            let coalesced = session("querycoalesce")
            await coalesced.connect()
            var edits: [Task<Void, Never>] = []
            for index in 1...5 {
                if index == 5 { coalesced.market = "FR"; coalesced.language = "fr-FR" }
                edits.last?.cancel()
                edits.append(Task { await coalesced.refreshCatalog("Original query \(index)") })
                if index < 5 { try await Task.sleep(for: .milliseconds(300)) }
            }
            for edit in edits { await edit.value }
            check(coalesced.isReady && coalesced.catalogError == nil
                  && coalesced.products.first?.title == "Original query 5 [requests=2,max=1]",
                  "Five delayed edits issue only one in-flight and one latest query, never producer capacity failure")
            check(coalesced.products.first?.market == "FR" && coalesced.products.first?.language == "fr-FR",
                  "Latest queued query retains its captured market/language instead of old request scope")
            await coalesced.disconnect()

            let dropped = session("querycoalesce")
            await dropped.connect()
            let active = Task { await dropped.refreshCatalog("Active original query") }
            try await wait { dropped.searching }
            let queued = Task { await dropped.refreshCatalog("Queued original query") }
            try await Task.sleep(for: .milliseconds(300))
            dropped.stopCatalogSearch()
            await active.value
            await queued.value
            check(dropped.catalogStopped && dropped.discoveryCheckedAt == nil,
                  "Stop clears the queued latest request while fencing the active bounded result")
            await dropped.refreshCatalog("After stopped queue")
            check(dropped.products.first?.title == "After stopped queue [requests=2,max=1]",
                  "A stopped queued query was never sent; the next explicit search remains usable")
            check(await dropped.disconnect(), "Stopped-query worker releases its owned process without an unbounded wait")
            for _ in 0..<3 {
                await dropped.connect()
                await dropped.refreshCatalog("Reconnected original query")
                let ready = dropped.isReady
                let closed = await dropped.disconnect()
                check(ready && closed,
                      "Repeated catalog-worker reconnect waits for owned-child exit and stays usable")
            }

            let selected = URL(fileURLWithPath: "/synthetic/selected/game")
            let inspected = session("inspection")
            await inspected.connect()
            await inspected.inspectInstallation(at: selected)
            check(inspected.inspection?.directory == selected.path
                  && inspected.inspection?.assessment.registered == false
                  && inspected.inspection?.assessment.launchable == false
                  && inspected.installedSnapshot == nil,
                  "Selected-folder inspection remains separate from registry, entitlement and launch")
            await inspected.disconnect()
            check(inspected.inspection == nil, "Inspection evidence clears when its engine disconnects")

            for scenario in ["inspectionmissing", "inspectionmismatch"] {
                let rejected = session(scenario)
                await rejected.connect()
                await rejected.inspectInstallation(at: selected)
                check(rejected.inspection == nil && rejected.inspectionError != nil,
                      "Missing or differently scoped inspection is an explicit error, never empty installed success")
                await rejected.disconnect()
            }

            let slowConfiguration = configuration("retireslow")
            let retiring = LiveSession(configuration: slowConfiguration)
            await retiring.connect()
            var firstFinished = false, secondFinished = false, fixtureAllowed = false, quitAllowed = false
            let firstClose = Task { let result = await retiring.disconnect(); firstFinished = true; return result }
            try await wait { retiring.phase == .disconnecting }
            let secondClose = Task { let result = await retiring.disconnect(); secondFinished = true; return result }
            let fixtureClose = Task { let result = await retiring.disconnect(); fixtureAllowed = result; return result }
            let quitClose = Task { let result = await retiring.disconnect(); quitAllowed = result; return result }
            let overlappingReconnect = Task { await retiring.connect() }
            try await Task.sleep(for: .milliseconds(150))
            let heldTrace = try trace(slowConfiguration)
            check(!firstFinished && !secondFinished && !fixtureAllowed && !quitAllowed
                  && retiring.connectionTransitioning && heldTrace.contains("stdin.closed") && !heldTrace.contains("exiting"),
                  "Actual child held after stdin EOF prevents early disconnect, fixture or quit success")
            await overlappingReconnect.value
            check(try trace(slowConfiguration).filter { $0 == "started" }.count == 1,
                  "Reconnect during shared retirement cannot start a second engine")
            let sharedResults = await [firstClose.value, secondClose.value, fixtureClose.value, quitClose.value]
            check(sharedResults.allSatisfy { $0 } && !retiring.connectionTransitioning,
                  "All overlapping disconnect callers observe the same completed child exit")
            await retiring.connect()
            let reconnectA = Task { await retiring.connect() }
            try await wait { retiring.phase == .disconnecting }
            let reconnectB = Task { await retiring.connect() }
            await reconnectA.value
            await reconnectB.value
            check(try retiring.isReady && trace(slowConfiguration).filter { $0 == "started" }.count == 3,
                  "Overlapping complete reconnect transitions spawn exactly one replacement, not two post-close engines")
            let superseded = Task { await retiring.connect() }
            try await wait { retiring.phase == .disconnecting }
            let supersedingClose = Task { await retiring.disconnect() }
            await superseded.value
            let supersedingResult = await supersedingClose.value
            check(try supersedingResult && retiring.phase == .disconnected
                  && trace(slowConfiguration).filter { $0 == "started" }.count == 3,
                  "Disconnect supersedes an entire pending reconnect before its post-close spawn")
            try cleanLifecycle(slowConfiguration)

            let failedConfiguration = configuration("retirefailed")
            let observer = ShutdownCheckObserver()
            let unobserved = LiveSession(configuration: failedConfiguration,
                                        shutdownClient: { await observer.close($0) })
            await unobserved.connect()
            let failedA = Task { await unobserved.disconnect() }
            try await wait { unobserved.phase == .disconnecting }
            let failedB = Task { await unobserved.disconnect() }
            let failedFixture = Task { await unobserved.disconnect() }
            let failedQuit = Task { await unobserved.disconnect() }
            await unobserved.connect()
            let failedResults = await [failedA.value, failedB.value, failedFixture.value, failedQuit.value]
            let observedAttempts = await observer.attempts
            check(try failedResults.allSatisfy { !$0 } && observedAttempts == 1 && unobserved.phase == .failed
                  && unobserved.errorMessage != nil && !trace(failedConfiguration).contains("exiting"),
                  "Actual failed short exit observation is shared and retains old ownership; fixture and quit remain blocked")
            await unobserved.connect()
            check(try !unobserved.isReady && trace(failedConfiguration).filter { $0 == "started" }.count == 1,
                  "A retry cannot overwrite an unobserved retiring child with a new engine")
            await observer.useDefaultBudget()
            check(await unobserved.disconnect(), "Retained ownership can reconcile the original child's eventual exit")
            await unobserved.connect()
            check(try unobserved.isReady && trace(failedConfiguration).filter { $0 == "started" }.count == 2,
                  "A new engine is allowed only after the retained child's exit is actually observed")
            check(await unobserved.disconnect(), "Recovered lifecycle test releases its last actual child")
            try cleanLifecycle(failedConfiguration)

            for scenario in ["retirehello", "retiresnapshot"] {
                let startupConfiguration = configuration(scenario)
                let starting = LiveSession(configuration: startupConfiguration)
                let startup = Task { await starting.connect() }
                try await waitForTrace(scenario == "retirehello" ? "hello.wait" : "snapshot.wait", startupConfiguration)
                let duplicate = Task { await starting.connect() }
                let interruption = Task { await starting.disconnect() }
                await duplicate.value
                let interrupted = await interruption.value
                await startup.value
                check(try interrupted && starting.phase == .disconnected && starting.hello == nil
                      && !starting.connectionTransitioning
                      && trace(startupConfiguration).filter { $0 == "started" }.count == 1,
                      "Disconnect fences suspended negotiation/snapshot continuations without stale startup or second spawn")
                await starting.connect()
                check(starting.isReady && !starting.connectionTransitioning,
                      "A fenced startup does not strand future explicit connection attempts")
                await starting.disconnect()
                try cleanLifecycle(startupConfiguration)
            }

            let diagnostics = session("diagnostics")
            await diagnostics.connect()
            let exportRoot = FileManager.default.temporaryDirectory.appendingPathComponent("XodusDiagnosticChecks-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: exportRoot, withIntermediateDirectories: false,
                                                   attributes: [.posixPermissions: 0o700])
            defer {
                do { try FileManager.default.removeItem(at: exportRoot) }
                catch { check(false, "Owned synthetic diagnostic export cleanup failed") }
            }

            let output = exportRoot.appendingPathComponent("summary.txt")
            await diagnostics.saveDiagnosticSummary(to: output)
            check(diagnostics.diagnosticExportError != nil && !FileManager.default.fileExists(atPath: output.path),
                  "Diagnostic export requires a current reviewed preview and creates no unreviewed file")
            await diagnostics.previewDiagnostics()
            guard let reviewed = diagnostics.diagnosticPreview else { throw ManagementError.invalidPayload }
            await diagnostics.saveDiagnosticSummary(to: output)
            check(try String(contentsOf: output, encoding: .utf8) == reviewed && diagnostics.diagnosticSaved,
                  "Export saves exactly the reviewed counts-only summary, without raw backend data")
            await diagnostics.saveDiagnosticSummary(to: exportRoot.appendingPathComponent("missing/summary.txt"))
            check(diagnostics.diagnosticExportError != nil && !diagnostics.diagnosticSaved
                  && diagnostics.diagnosticPreview == reviewed,
                  "Filesystem export failure is visible, never success, and preserves the reviewed summary for retry")
            guard let remote = URL(string: "https://example.invalid/diagnostics") else { throw ManagementError.invalidPayload }
            await diagnostics.saveDiagnosticSummary(to: remote)
            check(diagnostics.diagnosticExportError != nil && !diagnostics.diagnosticSaved,
                  "Diagnostic export rejects nonlocal destinations without writing")
            await diagnostics.disconnect()
            await diagnostics.saveDiagnosticSummary(to: output)
            check(diagnostics.diagnosticExportError != nil && !diagnostics.diagnosticSaved,
                  "Disconnect invalidates diagnostic preview before another export")
        } catch {
            check(false, (error as? ManagementError)?.localizedDescription ?? "Native fixture regression did not complete.")
        }
        print("\(count) native session checks, \(failures) failures. Mock children only; no Keychain or Microsoft operation.")
        return failures == 0
    }

    private static func wait(_ condition: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !condition() {
            guard ContinuousClock.now < deadline else { throw ManagementError.requestTimedOut }
            try await Task.sleep(for: .milliseconds(50))
        }
    }
}

private actor ShutdownCheckObserver {
    private(set) var attempts = 0
    private var budget: Duration = .milliseconds(200)

    func close(_ client: ManagementClient) async -> Bool {
        attempts += 1
        return await client.close(observationTimeout: budget)
    }

    func useDefaultBudget() { budget = .seconds(6) }
}
