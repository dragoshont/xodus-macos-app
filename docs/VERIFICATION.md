# Verification evidence

Recorded 2026-10-03. This is evidence for the **fixture foundation**, not live authentication, download, install or gameplay.

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

Hosted follow-up CI retrieval is currently blocked by a GitHub network timeout;
local Mac evidence is not relabelled as hosted CI. Full Store search, genuine
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
