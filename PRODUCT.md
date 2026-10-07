# Product

<!-- impeccable:product-schema 1 -->

## Platform

Native macOS, implemented with SwiftUI and AppKit. This is intentionally not a website, Electron shell or iOS layout stretched into a window.

## Users

Casual Apple Silicon Mac gamers who legitimately own or subscribe to PC games and want to sign in, see their eligible library, understand whether a title can run, install it and play without Terminal, Wine selection or DLL configuration.

## Product purpose

Make four independent questions understandable: **Do I have access? Can I download this PC package? Does this configuration run it? Is it installed here?** Do not compress these into a green "supported" badge. A catalog entry or play-history record is not proof of ownership.

## Positioning

An original Apple-native, standalone experience over the scoped Xodus management adapter. The mechanism is explicit entitlement, package and runtime evidence, not a broad promise that all Xbox PC games work on Mac. Heroic integration was considered; no shipping new-store plugin API has been established.

## Operating context

Develop and verify native code on the user's Mac over trusted SSH, using isolated public-app tooling. Public source must never include real library captures, account information or private runtime code. Official, separately installed CrossOver is the first-release dependency, not by itself certification of an Xbox-capable, exactly paired gameplay runtime.

## Capabilities and constraints

**Proposed v1:** account connection, entitled PC library, scoped catalog discovery, edition selection, explicit eligibility and compatibility, installation planning, durable downloads/recovery, launch, safe updates/removal and redacted diagnostics.

**Not promised in v1:** social features, achievements, cloud saves, checkout, cloud gaming, DLC management, all-PC-title support or a arbitrary runtime selector. Discover does not claim purchasability or ownership.

**Today:** a native development app with a real management client, paired native
authentication, public catalog, account-bound PC Library and a separate
explicit activity scope. Installed Play and game-service sign-in, Install,
Repair and save-preserving Uninstall are independently admitted, installed and
owner-live-accepted in bounded title/flow tests. Discover/owned-first search and
package-support checks are independently admitted, installed and owner-live-accepted
at `7c3c1f0`. Game Pass subscription/shelf, self-contained script paths, Setup
and Stop are the next source candidate, not installed evidence. Stable
app-owned Keychain ACL/migration is a separate approved, 2.5-hour next package
with synthetic two-build qualification and one allowed human migration approval;
no prompt-free replacement claim is made yet.
No complete owned-view parity or general gameplay certification is
claimed. Exact deployment and real provider evidence are recorded separately
in [native integration](docs/NATIVE-INTEGRATION.md), never inferred from mocks.
An explicit nonshipping `--fixture` mode retains the original demonstration;
its non-durable jobs and invented titles never become live evidence.

**User-decided:** original app code/docs/art use GPL-3.0-only, matching the user's stated Xodus licensing intent without assuming an "or later" grant.

**Shipping truth boundary:** the production compile excludes the offline demo's
views/state/art/resources and development check/export paths. Live screens use
actual public management data and honest native setup/empty/loading/error states,
not promotional synthetic game scenes. Shipping executes only an externally
approved, compiled-pin-bound bundled engine/helper pair; an unpaired repository
build fails closed. This source hardening is not shipping deployment or proven
human authentication. See [controlled admission](docs/SHIPPING-ADMISSION.md).

**User-directed first-release runtime policy (RT-01..04):** official CrossOver
is checked read-only using fixed standard locations and the approved
Apple-anchored CodeWeavers identity. Only verified observation defaults a
new/unset configuration; explicit decoded/selected profiles are preserved.
Missing or unverified CrossOver shows a gameplay prerequisite, without blocking
public browsing or sign-in. GPTK3/GPTK4, standalone/source-built Wine and custom
graphics are Experimental, requiring acknowledgement that resets on relevant
changes. Installation identity does not prove a license, ownership or gameplay.
Engine provenance/version and
graphics backend/provenance/version are independent: Wine 11 plus D3DMetal 4
is a composition, not an older GPTK Wine version. Configuration, installation,
device preflight and per-game verification remain distinct. Prefix generations
must be isolated, without silent reuse/migration/deletion of bottles or saves.
This separate source follow-up does not change the frozen authentication
contract, enable launch, import trial proof or establish redistribution rights.

**Proposed/pending:** macOS 14 deployment baseline; exact supported hardware/storage policy; third-party runtime redistribution; distribution/signing model; source of authoritative ownership and package authorization; subscription expiry behavior; compatibility verification governance. See [decision register](docs/RESEARCH.md).

## Brand commitments

Apple Games for macOS is the actual composition authority, not Xbox. The user
initially requested immersive artwork, floating transparent navigation and
edge-to-edge detail images, then rejected the bespoke rounded menu as non-native.
The latest user direction groups native navigation and compact scoped search
in the system bar, with a separate trailing Account control, no visible app
title and original artwork behind chrome. Real macOS 27 tabs have a segmented
14-26 runtime fallback; SDK 27+ is required to build. System controls, type,
focus and semantic appearance take precedence over hand-rolled pill geometry.
Actual macOS 26+ Glass is used where available, not ordinary material relabelled
as glass. SwiftUI/AppKit remains the native framework; UIKit was not a chosen
rewrite. An older native toolbar is deployed in the pairing recorded in
verification. This subsequent source correction includes shared stock search
and adaptive Account layout without changing routes or authentication behavior.
It is built/headlessly checked, not deployed or visually confirmed. Natural
artwork-dependent toolbar tint remains a compositor acceptance gate.

Directly observed Library compact three-column horizontal entries remain useful alongside the user-directed artwork-led featured/Continue Playing area. Each entry keeps access and compatibility separate. Discover has immersive features/browse/shelves, scoped Search, and no checkout promise. Navigation is Library / Discover / Downloads; Library remains the proposed default. No Apple logos/proprietary images/source, invented Friends/Arcade or Xbox-green identity. v0.1 was not approved and is explicitly superseded.

## Evidence on hand

The supplied research findings distinguish known CLI capabilities from unproven inventory, protocol and recovery. The privately viewed Apple Games Home is a reported visual observation; no screenshot or assets are published here. Historical private gameplay reports are not current compatibility verification. All public preview data and artwork are fictional.

## Product principles

1. Evidence before action: no install or play based solely on a successful exit code.
2. Access, package eligibility, compatibility and installation are independent.
3. Native simplicity by default; diagnostics never require a player to become a runtime engineer.
4. Interrupted work is recoverable; updates preserve the last runnable version and saves.
5. Public development never leaks private accounts or runtime material.

## Accessibility and inclusion

Full keyboard operation, VoiceOver names and ordered status announcements, reduced motion/transparency, readable resizing, light/dark appearance, localizable content, explicit offline states and no color-only meaning are production gates. The foundation supplies semantic native controls and a subset of these states; full assistive-technology testing is still a release gate.
