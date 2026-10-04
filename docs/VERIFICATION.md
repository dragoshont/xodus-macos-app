# Verification evidence

Foundation recorded 2026-10-03; subsequent native/read-only milestones are
identified separately below. None establishes successful human authentication,
game download, install or gameplay.

## Store search and adversarial-review app fixes

### Current inspection pairing and additional client fixes

One full Mac `sh tools/check.sh` invocation passed **14 core + 189 management +
24 presentation + 32 native session = 259 checks**, zero failures. The preceding
212-check `fb66a2d` app revision separately
[passed hosted CI](https://github.com/dragoshont/xodus-macos-app/actions/runs/37162534769);
that success is not attributed to the newer delta. Current native source
`6750219cf547b693d29ee162d796b9b39c37ca70` independently
[passed hosted CI](https://github.com/dragoshont/xodus-macos-app/actions/runs/37165029761).

The same retained reviewer closed app R01-R04 at `fb66a2d` and backend R05-R07.
Two subsequently confirmed app findings are fixed with new regressions:
R08 preserves source-level PACKAGE_UNAVAILABLE without optional details and
allows a subsequent snapshot on the same connection; malformed present details,
including null, are still rejected. R09 coalesces catalog work into one active
plus the latest captured query/market/language. Five delayed edits at 300 ms,
cancelling prior view tasks, issue only two requests with max concurrency one
against a mock that enforces the producer's four-operation limit. Latest scope
results arrive without manual refresh; stop drops unsent queued work. These
new fixes require review of their persisted revision before human readiness.

Canonical schema/fixtures at producer `e3129cee422305657b945d35daf2f780ffe98e2b`:
SHA256 `c95c3fabdf114f89329d2361e76421e7b47be4c113f56c2381e64d437e44f749`,
79 positive / 20 negative / four evidence-edge frames. Immutable bytes were
copied and checked; new UUID and exclusion constraints are enforced by the
consumer. Enabled-inspection unsigned engine SHA256:
`da548dd5abe4c32dc17035817d1a809a31c8eb19e615f26dad079a245cf72178`;
locally signed embedded SHA256:
`2180d02dca9300d08c91384207fed6acebdeaaa9d0c309bc0fd28a7fcf7b2296`.
Release compilation, resource/plist and ad-hoc-signature checks passed.

The unsigned producer passed 21 actual checks before the shutdown refinement;
the signed embedded copy passed **22 actual checks** including observed owned
exit. The committed `--probe-inspect` runner creates only its own original
4096-byte synthetic marker under a canonical private test root and removes it.
Its 196-byte digest/version matches; marker and management.json bytes stay
unchanged. Missing/aliased/malformed fixtures remain typed failures, and the same
connection can read the installed snapshot afterward. This is not external-game
inspection, full integrity, retail mapping, ownership, registration or gameplay.
Original layout provenance is the pinned public producer smoke helper; no key
material or real game data is copied.

Normal LaunchServices app PID 65869 / owned child 65872 passed noninteractive
Account/Check status/Close, real public Halo typing through an exact focused
native field, and native continuation. The helper refuses to replace a preexisting
query or type with a sheet open, and logs only authored allowlisted labels.
No consent/sign-in was initiated. Native picker compilation is separate from an
actual user-selected external-folder test, which has not occurred.

The same signed bundle subsequently passed graceful normal-app quit: both
owned PIDs exited before another app was opened. Relaunched app PID 67493 /
child 67496 passed Account/Check status/Close and retained the same signed
engine hash. This additionally exercises the new bounded shutdown through the
actual application delegate, not only mock-child checks. No consent was started.

Live upstream zero-source behavior is **not observed**: arbitrary nonsense can
return suggested cards. The empty-source regression remains scoped to
deterministic backend serve tests and actual LiveSession/mock-child checks;
positive HTTP queries do not strengthen it into a live empty-result claim.

An expanded native run stalled during owned-process close. The exact mock-only
stack showed Foundation `NSConcreteTask.waitUntilExit` blocked in its private
run loop after the child was gone. That run was stopped, not counted as passing.
Bounded six-second exit observation replaced the unbounded wait; failure is
explicit and prevents reconnect/fixture switch/quit from pretending cleanup
finished. Three repeated worker reconnects and the complete suite then passed.

### Earlier query milestone (historical)

Recorded 2026-10-04. One complete `sh tools/check.sh` invocation passed **14 core +
156 management + 24 presentation + 18 native session = 212 checks**, zero
failures. Native checks execute the actual session coordinator against sanitized
synthetic child processes and exit before creating a window. They exercise:

| Finding / edge | Actual regression evidence |
| --- | --- |
| R01 expired profile | Explicit current status exposes confirmed launcher disconnect; fresh signed-out state precedes a new sign-in |
| Permission failure after expired status | Disconnect disabled; attempted unavailable-store recovery makes no deletion request and preserves the profile |
| R02 transient polling / rejected late cancel | Status remains available while pending; one inaccessible-store error recovers; INVALID_TRANSITION resumes polling to a terminal result, never false cancellation |
| R03 human operation budget | Synthetic preparation/logout exceeds the old 30-second limit while public snapshots still respond; finite 600-second mutation budgets remain distinct from short reads |
| Uncertain mutation | Failed preparation invalidates pre-mutation freshness; explicit fresh status required before another attempt; transport timeout separately tested with reconnect/status reconciliation |
| R04 initial all-failure page | Continuation exposed with zero products; later success retains earlier failures and unknown entitlement |
| Empty / stopped query | Genuine empty success remains live and distinct from failures; stop fences a late bounded result without claiming HTTP abort |

Canonical schema pin is `9d024ae079daccafb3437e4b0c67aef735d657bb`, SHA256
`655e1ed31772b35a8526ef5a0986557e7f6de689d5c4925ccde7041bc33b5f29`,
with 77 positive, 15 negative and four independent evidence-edge frames.
All four exact fixture hashes were checked against immutable public Git bytes.

**Thirteen actual read-only checks passed** against preserved producer
`4de9c2b2e7c114854699e3708d41c12fa73e188d` and its signed embedded copy:
two bounded Microsoft Store query pages, two discovery pages and checked-cache
title search, negotiation/session identity, registry and redacted diagnostics.
Unsigned SHA256 `58f5b80f253d8ee199dc193d3a31cbd1571b641ce309f81bf0430910a6982e83`;
embedded SHA256 `5ea5b49610fc9887345234e0d66bc9954f3bf1e78716ab25866802c4f48f324b`.
Release compilation, resources, plist and signature checks passed.

Normal LaunchServices app PID 39706 / embedded child 39709 exposed Account,
noninteractive saved-status refresh, explicit Check status and Close. Discover
retained the engine beyond 35 seconds. These are bounded owned-window authored
label checks, not successful sign-in or full VoiceOver. No consent was initiated.

**This producer was not review-closed at that milestone.** The retained reviewer subsequently found
R06 (zero-source query cached as an invalid empty registry operation) and R07
(repeated source-cursor equivalence not fully normalized). Positive two-page
evidence above could not close either issue. Their later producer closure and
current pairing are recorded above; live zero-source evidence remains unobserved,
not fabricated from an arbitrary query. App R01-R04 later closed at `fb66a2d`;
no new reviewer was spawned.

Hosted startup-fix revision `44f24407ad9562e90a305426771423e3f46864dc`
[passed its own GitHub Actions run](https://github.com/dragoshont/xodus-macos-app/actions/runs/37159377257).
That success is not attributed to these newer changes.

## Bounded discovery and default application startup

Follow-up recorded 2026-10-04: the initial PID graph below did **not** establish
sustained startup. Bounded own-window inspection subsequently found the local
timeout message and no engine child. Added privacy-safe OSLog evidence identified
`auth.status` as the exact stalled GUI request; hello and activity negotiation
succeeded, and a same-state SSH probe confirmed matching hello/snapshot session
identities. No native permission was approved.

Anonymous startup now performs registry/catalog work without a Keychain read.
The rebuilt normal LaunchServices app retained its included engine beyond the
original 30-second failure deadline. Exact-PID/bundle/window-checked Accessibility
presses successfully opened **Discover, Downloads, Library and Account**. The
account sheet exposed the authored unchecked-status explanation; it did not read
credentials or start sign-in. Navigation and profile controls now have explicit
button/press semantics and stable identifiers. The committed helper logs only
allowlisted public UI labels, not product/account data. This confirms bounded
normal startup/navigation, not full VoiceOver, live compositor or account consent.

The discovery follow-up passed **14 core + 130 management + 24 presentation =
168 checks**, zero failures. Canonical schema is now producer commit `790f5c4`,
SHA256 `2ede71d5171cf4dc1659fedfc99187a90d904d9264119a22ee9f94064baef3d2`;
the preserved discovery implementation/executable is `8718dcb`. Seventy-one
positive, eleven negative and four evidence-edge fixtures remain sanitized.
All-failure pages validate only against the explicit error definition; an empty
page cannot masquerade as successful discovery. Source language and same-base
neutral fallback, inaccessible-Keychain errors and scoped catalog invalidation
are covered.

**Eleven actual engine checks passed**, including explicit hello/snapshot session
identity and two source-backed anonymous PC Game
Pass discovery pages with distinct identities/stable cursor, and actual title
search in the resulting checked cache. This is not global Store search or owned
inventory. The refined authentication result identifies an inaccessible
credential store; no Keychain approval, credential replacement or sign-in was
performed.

The release app was rebuilt with that preserved engine, locally signed and
resource-checked. Unsigned input SHA256 is
`14dd06466a201ddb77fe7c2d6f9a57bbbb79788f03413989e5158d9053c864ad`;
embedded local SHA256 is
`62cb9564478d2a2bcee472b6f7d6865f5f3007a0314e30c7a06537523820f175`.
Actual default LaunchServices entry (`open Xodus.app`, no live/backend flags or
environment override) started the application and its own included-engine child.
That initial PID/parent relationship established default embedded selection only;
the failed sustained startup and its verified correction are recorded above.
Missing/nonexecutable embedded engines show
an actionable error and do not silently reuse saved developer binaries or fixtures.

Hosted startup follow-up subsequently succeeded for `44f2440`, as recorded above;
local Mac evidence is not relabelled as hosted CI. Full search coverage, genuine
ownership, authorized install/update/play/recovery and coordinator-owned adversarial
review/findings closure remain active completion prerequisites.

## Native client implementation

The subsequent native development app now opens a real management shell by default;
the original demonstration requires `--fixture`. On the same isolated Mac,
`sh tools/check.sh` passed **14 core + 118 management + 24 presentation = 156
checks**, zero failures. The management checks use the immutable producer pin
and sanitized corpus documented in [native integration](NATIVE-INTEGRATION.md),
plus actual mock child processes; no Microsoft login or Keychain permission was
approved by these checks.

The checks cover strict request/result correlation, capability gating, split and
oversized JSONL, truncated output, unknown IDs/shapes, process exit/EOF/timeouts,
independent evidence and activity sequence/revision invariants. In-flight activity
snapshots fence incoming events: the snapshot is applied first and newer buffered
events are applied afterward, avoiding a legitimate live-event/snapshot race.
Failed reconciliation retains the last verified jobs as non-current and disables
mutation until an authoritative snapshot is restored.

`sh tools/build_app.sh` also built the release `.app`, generated the original icon,
copied required resource bundles and the GPL notice, and passed plist/ad-hoc
signature verification. The packaged executable's resource/presentation check
passed. This is a local development bundle, not a notarized release.

Disconnected own-view Library/Discover/Downloads exports were inspected in a
bounded correction/confirmation pass. The native search placeholder and centered
empty states were corrected; no account data or desktop capture was involved.
Exports still omit live compositor/backdrop effects.

The published native-auth schema and sanitized fixtures are pinned at producer
commit `b9cd60bf51cd4cb8e864318cd0c4316453b4b8df` (68 positive, ten negative,
four independent evidence frames). Against the preserved native engine, a
**seven-check read-only interoperability probe passed against both the preserved
engine and its ad-hoc-signed embedded copy**: hello, unsupported
runtime/plan gates, explicit invalid-credential failure, partial observed catalog,
durable jobs snapshot, management-only installed registry and redacted diagnostics.
`auth.status` returned **AUTH_INVALID**, not valid sign-in; this account gate was
reported to the backend owner. No permission was approved and no authentication,
logout, installation or game process was started.

The verified unsigned input engine SHA256 is
`3fd646ac3eb7bdd2acdbcc3ed3755d2f4e2722ea1a7b4798eae72acb7ac41fd7`;
its locally ad-hoc-signed embedded copy is
`39df33fbac4334df12de39fb2e345a1ac64eb9e4330bb7a1f78de59b6fc26976`.
The packaged resource/presentation check passed. A successful real account login,
owned inventory, game installation or gameplay is **not** claimed. Hosted CI
evidence below remains evidence for its named foundation commit until the new
revision's run is separately recorded.

## Actual Mac environment

Apple Silicon arm64; macOS 27.0.1 build 26A434; Swift 6.4 (`swiftlang-6.4.0.34.1`); SDK 27; developer directory `/Library/Developer/CommandLineTools`. Full Xcode was unavailable and was not installed. Public source was transferred into the new isolated `~/xodus-app-tooling/app-foundation` directory, excluding git/credentials. No private runtime repositories, services, games, bottles or capture helpers were modified.

## Passed commands and observations

| Check | Actual result |
| --- | --- |
| `swift build` | Native SwiftUI executable and core/check targets built successfully for arm64 with proposed macOS 14 deployment target |
| `swift run XodusFixtureChecks` | 14 core checks, 0 failures |
| `swift run XodusPreview --self-check` | 15 presentation/resource checks, 0 failures; no window or backend needed (29 total checks with core) |
| `sh tools/check.sh` | All three commands above passed as one reproducible invocation |
| Native executable launch | On-screen native window verified through CoreGraphics, 1200 x 860 points; no runtime/game process launched |
| Actual macOS 26+ Glass APIs | `glassEffect(.regular.interactive(), in: Capsule())`, `GlassEffectContainer`, `.glassProminent` compiled and ran on macOS 27 CLT with older availability fallback |
| Own native view export | Three actual fixture NSView hierarchy PNGs exported in-process; Library/Discover/Downloads inspected in a bounded correction + confirmation pass |
| Native confirmation | White/legible local overlay chrome and original image-backed heroes/content confirmed by coordinator. Search prompt then received an explicit light style as a narrow coupled fix |
| `python tools/generate_mockups.py` | Nine editable SVGs generated using Python standard library; all parse as valid XML |
| `swift tools/render_mockups.swift` | All nine original SVGs rendered through native WebKit into PNG previews without third-party dependencies |
| PNG artifacts | Nine 2880 x 1960 Retina previews retrieved to `design/previews` |
| Original image resources | Six original bundled images loaded in self-check; primary 2048 x 1152 authored scenes use committed CoreGraphics/ImageIO source; no external images/service |
| v0.2 SVG upload budget | All nine self-contained data-URI screens <= 0.90 MB each, below 10 MB cap; editable text/vector layout with original JPEG derivatives |
| Figma revision | Nine v0.2 editable imports succeeded; Library/Discover official renders inspected by coordinator. Some gradient/rounded-image fidelity flattened; no compositor proof. Earlier unapproved v0.1 superseded |
| GNU GPL v3 | Verbatim 35,149-byte GNU license text retrieved from `https://www.gnu.org/licenses/gpl-3.0.txt`; app grant is explicitly GPL-3.0-only |
| Hosted GitHub Actions, code commit `4e9c963` | [Fixture foundation checks succeeded](https://github.com/dragoshont/xodus-macos-app/actions/runs/37151989754): native build/check sequence and SVG regeneration |

The check executables cover six image resources plus independent access/package/compatibility gates, subscription expiry, stale/offline/partial inventory, mismatched runtime/architecture, exact disk-space threshold, cancelled/completed job non-regression, pause/retry, identity/JSON round trip, scoped search/category/access filter, duplicate enqueue, completed-only installation, disconnected action denial and fixture reset.

## Toolchain constraints resolved

SDK 27 exposes a new `SwiftUI.State` macro whose plugin is not shipped with this CLT. The first `@State` build failed with `external macro implementation type 'SwiftUIMacros.StateMacro' could not be found`. The app uses standard native `ObservableObject`/`StateObject` for sheet interaction instead, compatible with the proposed older baseline; no private SDK plugin, type-erasure workaround or web fallback was introduced.

This CLT has neither XCTest nor Swift Testing (`no such module`/unresolved dependency). Rather than install Xcode or introduce a dependency solely for fixture assertions, tests are explicit failing Swift executables: `Tests/FixtureChecks/main.swift` and `Sources/XodusPreview/PreviewChecks.swift`. **Do not claim `swift test` passed**; use `sh tools/check.sh`. Swift's new build system also emitted non-fatal linker warnings for absent CLT `Developer/usr/lib` and `Developer/Library/Frameworks` search paths; compilation/link/run/checks nevertheless succeeded.

## Not yet verified

Static SVG translucency is a **placement/composition concept**, not native Liquid Glass. Actual framework calls were verified separately by compile/run. Own-view AppKit exports omit compositor/backdrop effects: absent glass surfaces and transparent/black titlebar strips are export limitations, not evidence of live-window refraction or titlebar alpha fidelity. No desktop/other-app capture or new Screen Recording permission was used. The coordinator confirmed native Library/Discover navigation via Accessibility on the earlier fixture window; that does not replace complete current VoiceOver or live compositor testing.

The native client and bounded read-only producer interoperability are verified as recorded above; successful account consent/provider authorization remains a separate gate. Owned-PC enumeration, game package download/installation, real game recovery, runtime pairing download, gameplay, notarized distribution and save preservation remain unavailable. Actual macOS 14 runtime behavior is not verified merely because a macOS 14 deployment target compiles on macOS 27. Full VoiceOver, keyboard sheet focus return, both appearances, reduced-preference, localization/RTL, performance and resize matrices remain release gates. Hosted CI evidence above is for the named code commit, separate from local Mac verification; later revisions need their own workflow read.

Fixture jobs deliberately reset on relaunch. The fixed fixture evidence time and illustrative 24-hour access freshness gate are demonstrations, not a proven upstream authorization TTL.
