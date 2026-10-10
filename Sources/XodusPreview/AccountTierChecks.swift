// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import XodusManagement

@MainActor
enum AccountTierChecks {
    static func run(check: (Bool, String) -> Void) {
        // Signed out: no entitlement claim of any kind.
        let signedOut = AccountEntitlements.derive(signedIn: false, held: [.purchased], gamePassActive: true)
        check(signedOut == .signedOut && signedOut.tiers.isEmpty && signedOut.summary == "Not signed in",
              "M10: signed-out account makes no owned or Game Pass claim")

        // Owned: a purchased held entitlement, no Game Pass probe.
        let owned = AccountEntitlements.derive(signedIn: true, held: [.purchased], gamePassActive: false)
        check(owned.ownsGames && owned.gamePass == .inactive && owned.tiers == [.owned]
              && owned.summary == "Owned library",
              "M10: purchased held entitlement is Owned and not Game Pass")

        // Owned (unknown kind): a held entry of unknown acquisition is still owned (account-held).
        let ownedUnknown = AccountEntitlements.derive(signedIn: true, held: [.unknown], gamePassActive: false)
        check(ownedUnknown.ownsGames && ownedUnknown.tiers == [.owned],
              "M10: unknown-kind held entitlement counts as Owned, never a subscription grant")

        // Game Pass PC: probe active with no owned entitlements.
        let pass = AccountEntitlements.derive(signedIn: true, held: [], gamePassActive: true)
        check(!pass.ownsGames && pass.gamePass == .active(.pc) && pass.tiers == [.gamePass(.pc)]
              && pass.summary == "PC Game Pass",
              "M10: active PC probe is PC Game Pass access without implying ownership")

        // Both: owned purchase and active PC Game Pass coexist on independent axes.
        let both = AccountEntitlements.derive(signedIn: true, held: [.purchased], gamePassActive: true)
        check(both.ownsGames && both.gamePass == .active(.pc)
              && both.tiers == [.owned, .gamePass(.pc)] && both.summary == "Owned library + PC Game Pass",
              "M10: ownership and Game Pass access are independent and can both hold")

        // Subscription-grant only: a Game-Pass-granted held entry proves active Game Pass but
        // is NOT ownership, and the plan stays undetermined without the account-bound PC probe.
        let grant = AccountEntitlements.derive(signedIn: true, held: [.subscription], gamePassActive: false)
        check(!grant.ownsGames && grant.gamePass == .active(.undetermined)
              && grant.tiers == [.gamePass(.undetermined)] && grant.gamePassPlanUndetermined
              && grant.summary == "Game Pass",
              "M10: subscription grant is active Game Pass, never Owned, and never a fabricated plan")

        // A positive probe pins the plan to PC even when a subscription grant is also present.
        let grantProbed = AccountEntitlements.derive(signedIn: true, held: [.subscription], gamePassActive: true)
        check(grantProbed.gamePass == .active(.pc) && !grantProbed.ownsGames
              && !grantProbed.gamePassPlanUndetermined,
              "M10: the account-bound PC probe outranks grant evidence for plan detection")

        // Free: signed in with neither owned entitlements nor Game Pass access.
        let free = AccountEntitlements.derive(signedIn: true, held: [], gamePassActive: false)
        check(free.tiers == [.free] && !free.ownsGames && free.gamePass == .inactive
              && free.summary == "Free",
              "M10: signed-in account with no entitlements is Free")

        // Expired/unknown: a withdrawn/removed collection (no held entries) with an inactive probe
        // never resurrects ownership or active Game Pass, and invents no expiry.
        let expired = AccountEntitlements.derive(signedIn: true, held: [], gamePassActive: false)
        check(!expired.ownsGames && !expired.gamePass.isActive && expired.tiers == [.free],
              "M10: expired/unknown access does not survive as Owned or active Game Pass")

        // Mixed held set: a subscription grant alongside a purchase is still Owned (the purchase).
        let mixed = AccountEntitlements.derive(signedIn: true, held: [.subscription, .purchased], gamePassActive: false)
        check(mixed.ownsGames && mixed.gamePass == .active(.undetermined)
              && mixed.tiers == [.owned, .gamePass(.undetermined)],
              "M10: a purchase in a mixed held set yields Owned while grant evidence yields Game Pass")

        // Console/Ultimate are representable but never auto-emitted from available signals.
        let allTiers = [owned, ownedUnknown, pass, both, grant, grantProbed, free, mixed].flatMap(\.tiers)
        let emitted = Set(allTiers.compactMap { tier -> GamePassPlan? in
            if case let .gamePass(plan) = tier { return plan } else { return nil }
        })
        check(!emitted.contains(.console) && !emitted.contains(.ultimate),
              "M10: Console and Ultimate are modeled but never fabricated from PC-only signals")

        // Per-title eligibility is the audited distinction: installation alone is never Owned.
        let installedOnly = LibraryGame(id: UUID().uuidString, title: "Local only", installed: nil,
            pc: nil, product: nil, owned: false, gamePass: false)
        check(installedOnly.eligibility == nil,
              "M10: a record with no installation, entitlement or access has no eligibility")
    }
}
