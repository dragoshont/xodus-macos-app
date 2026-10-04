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
        func session(_ scenario: String) -> LiveSession {
            let executable = URL(fileURLWithPath: CommandLine.arguments[0])
                .deletingLastPathComponent().appendingPathComponent("XodusManagementChecks")
            let state = FileManager.default.temporaryDirectory
                .appendingPathComponent("XodusNativeChecks-\(UUID().uuidString)").appendingPathComponent(scenario)
            return LiveSession(configuration: BackendConfiguration(executable: executable, stateDirectory: state))
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
            await uncertain.refreshAccount()
            check(uncertain.accountStatusCurrent && uncertain.canSignIn,
                  "A fresh status read is required to recover from failed sign-in preparation")
            await uncertain.disconnect()

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
