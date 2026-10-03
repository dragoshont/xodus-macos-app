# Research evidence and open decisions

Recorded 2026-10-03. This foundation consumes **supplied prior research**, not fresh network observation or runtime revalidation. Public links below are evidence pointers; no Xbox desktop traffic capture, TLS/proxy interception, credentials or purchases were performed.

## Evidence ledger

| Finding | Classification | Consequence / limitation |
| --- | --- | --- |
| Apple Games Home: centered Home/Arcade/Friends/Library/Search, profile trailing, restrained chrome, editorial hero, compact Continue Playing and shelves | Supplied private visual observation | Visual authority only; no assets or screenshots copied. Xodus uses Library/Discover/Downloads and original art. |
| Apple Games Library: summary then Your Games/count/sort-filter, compact three-column horizontal entries with square icons, title/played-added metadata, compatibility warning and Play/View pill | Supplied new direct private window observation | Stronger Library-specific authority: adopt compact rows in Library; reserve editorial hero/shelves for Discover. No content/capture published. |
| Apple Games Search: centered navigation persists, broad centered search field, restrained genre/category browse at empty query | Supplied new direct private window observation | Scoped Library/Discover field; useful empty-query category browse distinct from results/no-match/offline/loading. No source assets copied. |
| User explicitly rejected v0.1 flat mockups and requested modern rounded floating transparent menu, immersive images and closer Apple Games composition | User-directed correction | v0.2 uses actual macOS 26+ Glass, full-bleed feature/detail art, separate circular profile, compact Library entries alongside featured/Continue Playing. Earlier imports are superseded, not approvals. |
| Apple published Landmarks sample demonstrates Mac Liquid Glass and edge-to-edge imagery; SwiftUI/AppKit Glass APIs available on macOS 26+ | Supplied official-documentation review; actual SDK27 app build verification | No UIKit rewrite necessary. No Apple Games source/asset copied. Static SVG/native NSView exports cannot prove compositor refraction. |
| Xodus CLI provides auth, package download/extract/stream, Unix run and product-ID metadata lookup | Supplied prior private source review | Useful foundation, not proof of complete search, owned enumeration, stable machine protocol or safe install lifecycle. No private source included. |
| Backend Keychain abstraction exists in `crates/xodus/src/tokens/backend/keychain.rs`; `secrets.rs` selects `apple_native_keyring_store::keychain` normally on macOS; optional `key-chain-file` persists `.xodus-keyring.ron` | Parent's supplied direct current source verification | Reuse one existing credential owner; forbid file-backed feature in shipping app. No private implementation copied. |
| `displaycatalog.rs` offers only `find_products_by_id`, GET `displaycatalog.mp.microsoft.com/v7.0/products/{product}?market=...&languages=...`, propagating HTTP errors | Parent's supplied direct current source verification | ID lookup established; full-text catalog search remains unverified. No claim that catalog search currently exists. |
| `start_new_session` uses Xbox Live flow/scopes and `get_xsts_token` accepts a relying party | Parent's supplied direct current source verification | Existing machinery does not prove inventory authorization; record audience separately per capability. |
| Interactive package prompts; inner streaming failure may yield outer success; login may report success without tokens | Supplied prior source review | Adapter requires structured results/credential proof/terminal registry evidence; never trust exit alone. |
| Streaming reuses hashed files and redownloads changed files | Supplied prior source review | Not a block-delta patch guarantee. Durable version/recovery/removal safety unestablished. |
| Exactly paired Xbox-capable Wine runtime required | Supplied technical constraint | Stock Heroic Wine/CrossOver cannot be substituted; pairing and redistribution remain gates. |
| Several private gameplay successes historically reported | Historical private reports, not revalidated | No public verified-game list or compatibility claim derived from them. |
| Heroic new-store plugin proposal remains a proposal | [Public issue #3158](https://github.com/Heroic-Games-Launcher/HeroicGamesLauncher/issues/3158), supplied review | No proven shipping plugin API; standalone app selected. Do not interpret this as a freshly checked issue status. |
| Public Game Pass candidate discovery uses catalog/display catalog endpoints | [NikkelM/Game-Pass-API](https://github.com/NikkelM/Game-Pass-API), [scraper source](https://github.com/azxie/gamepass-scraper/blob/master/find_game_ids.py), prior source-derived leads | `catalog.gamepass.com/sigls/v2` and `displaycatalog.mp.microsoft.com/v7.0/products` are catalog leads, not observed desktop API traces or ownership. Region/platform/paging/freshness need proof. |
| Microsoft Inventory Service + XSTS might support consumer inventory | [Historical Xbox Live API issue comment](https://github.com/microsoft/xbox-live-api/issues/575#issuecomment-1105826347) | Historical lead only: audience, pagination, current availability, PC purchases and subscriptions unproven. |
| Publisher Collections APIs query entitlements | [Microsoft GDK documentation](https://learn.microsoft.com/en-us/gaming/gdk/docs/store/commerce/service-to-service/xstore-query-user-entitlements) | Partner-oriented, not turnkey consumer library. Their scope does not prove a consumer route impossible. |
| Xbox desktop accessibility exposed Home/Game Pass/My Library/Store/Search and Library MyGames/PlayLater/PlayHistory/InstallQueue | Supplied accessibility observation | Navigation/network observation did not succeed; do not claim captured APIs or inventory semantics. |
| Ownership title history is not inventory | Product/research conclusion | Misses never-played purchases and includes expired subscription play; can enrich but cannot authorize. |
| macOS design and modern glass guidance | [macOS HIG](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos), [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass) | Use native controls and availability-aware system behavior, not web glass styling. |

## Decision register

| ID | Status | Decision / question | Evidence needed to close |
| --- | --- | --- | --- |
| D-01 | Confirmed direction | Public standalone SwiftUI/AppKit app; private runtime remains separate | User brief |
| D-02 | Proposed | Library default; macOS 14 deployment baseline | User acceptance, hardware/OS coverage and native API availability tests |
| D-03 | App license confirmed; redistribution pending, release blocker | User chose GPL v3; app SPDX is GPL-3.0-only. Runtime/components keep their own licenses | Verbatim GPL v3 in LICENSE; separate dependency/runtime legal review needed before packaging |
| D-04 | Pending, release blocker | Consumer auth and authoritative owned-PC inventory | Approved audience/consent, all pages, never-played purchase, expired subscription, console-only, regional variants |
| D-05 | Pending, release blocker | Package eligibility/edition mapping | Authorized sample mapping, architecture/language/market validation; no purchase required for this foundation |
| D-06 | Pending, release blocker | Management protocol and durable lifecycle | Backend contract review + crash/cancel/disk/integrity/rollback fault tests |
| D-07 | Pending, release blocker | Signed runtime manifests/pairing | Reproducible build, signer trust, hash verification, capability/version pairing and rollback |
| D-08 | Pending | Distribution/update model | `.app` bundling, signing/notarization, installer/updater selection and component licenses |
| D-09 | Pending | Offline entitlement and revoked-access policy | Authorized source expiry semantics, backend signed policy and user-facing rules |
| D-10 | Pending | Compatibility verification governance | Consentful testing, reproducible OS/hardware/runtime fingerprint and revalidation cadence |
| D-11 | Pending | Storage retention / save-format rollback | Exact staging and rollback overhead, reclaim policy; title-specific save compatibility |
| D-12 | Pending, production asset gate | Title-specific catalog image rights/cache policy | Licensed source/attribution/cache review; current authored illustrations are fixture placeholders only |

## Research gates, without blocking design

Specifications and fixture UI can proceed now. Live inventory/auth must not ship until D-04 closes; avoid presenting catalog-only, title-history or partner-only results as a solved library. A failed research route narrows the evidence, not the universe of possible consumer APIs. Use documented, authorized investigations; no TLS interception, credentials or private captures belong in this public repository.
