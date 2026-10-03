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
