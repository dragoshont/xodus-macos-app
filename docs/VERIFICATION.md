# Foundation verification

Recorded 2026-10-03. This is evidence for the **fixture foundation**, not live authentication, download, install or gameplay.

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

No real sign-in, ownership enumeration, catalog search API, package download, installation, durable recovery, runtime pairing download, gameplay, signed distribution or save preservation is implemented or tested. Actual macOS 14 runtime behavior is not verified merely because a macOS 14 deployment target compiles on macOS 27. Full VoiceOver, keyboard sheet focus return, both appearances, reduced-preference, localization/RTL, performance and resize matrices remain release gates. Hosted CI evidence above is for the named code commit, separate from local Mac verification; later revisions need their own workflow read.

Fixture jobs deliberately reset on relaunch. The fixed fixture evidence time and illustrative 24-hour access freshness gate are demonstrations, not a proven upstream authorization TTL.
