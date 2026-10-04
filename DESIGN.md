# Design system: immersive native content, system toolbar revision

## User-directed visual contract

Apple Games for macOS is the **actual composition/layout authority**, not loose inspiration. The user rejected the flat v0.1 interpretation and later the bespoke floating-menu interpretation. The current direction is immersive artwork under a translucent native bar, grouped native navigation/search, a separate trailing account control and no visible app title. The framework remains SwiftUI/AppKit, not a UIKit rewrite.

The subsequent user critique rejected the hand-rolled rounded menu as non-native.
The navigation correction uses the real macOS window toolbar: a centered native
Library / Discover / Downloads picker, compact stock search and a trailing account
button. System chrome owns geometry, selected/focus state, appearance and
background; no custom capsule selection or forced white/dark toolbar treatment.
Keep the original artwork-led content, traffic lights and routes, without a web
sidebar, Xbox-green brand or copied Apple logo/art/source. The system toolbar
is deployed in an older source pairing; the grouped search, artwork-under-chrome,
Account and Scene corrections below remain separately staged, not deployed or
visually confirmed.

## Surfaces

**Library (Operate):** original immersive focused-game area, scoped Search, compact Continue Playing, then Your Games/count/filter-sort. Three columns of horizontal square-icon entries at roomy widths, fewer when resized. Title, access, compatibility and contextual View are separate. The compact Library observation remains important, but no longer prohibits the featured imagery explicitly requested by the user.

**Discover (Operate/explore):** immersive original environment, one title/action, empty-query categories and catalog shelf. Typing shows scoped results rather than fake empty-query results. Catalog presence never proves ownership.

**Detail/install/downloads (Operate):** full-bleed detail image, four independent evidence rows and one reasoned action; protected installation sheet with space/experimental consent; flat progress rows and recoverable errors. Artwork never replaces evidence.

## Actual native implementation

`XodusToolbar` uses a principal `ToolbarItemGroup`, a real `.tabs` `Picker` on
macOS 27+ with a `.segmented` fallback on 14-26, stock `NSSearchField` and an
ordinary trailing toolbar `Button`. These are platform controls, not a
third-party kit or custom navigation shape. SDK 27+ is a build requirement,
independent of the proposed runtime baseline. The picker writes through
`AppState.navigate`, preserving scope resets and Command-1/2/3 routes. The
Scene's hidden-title-bar style and unified toolbar retain traffic lights and
window/menu/Dock identity while content extends only under the top container
safe area. The fixture-only path shares this navigation but
its Account button still opens only invented onboarding.

The toolbar and development/fixture status use semantic system appearance.
Remaining content actions use actual `.glassProminent` on macOS 26+, with normal
native fallbacks on older systems. `NativeGlass` remains available for other
content surfaces, not for repainting toolbar controls. Reduced transparency and
body light/dark treatment remain native. There is no fake CSS glass or private
SDK import.

The live development shell inherits this world without copying fixture game names or covers. It uses a labelled original landscape, a separate native account sheet and centered unavailable/empty states. The same scoped `NSSearchField` supplies toolbar search in live and fixture views: system bezel, search/cancel controls, semantic appearance and the existing field editor/focus binding. Empty unfocused search occupies 32 pt; editing, Command-F or nonempty text expands it to 220 pt. Downloads retains disabled search, and live Library eligibility rules remain unchanged. There is no duplicate hero search, wrapper icon, forced dark scheme or custom capsule. Fixture/development notices remain inside content rather than an opaque strip above the hero. Checked real public products use honest native icon placeholders until rights-cleared title artwork exists. Four-facet detail does not turn catalog presence or saved sign-in into ownership. The original orbital-doorway app icon is reproducible with `tools/RenderAppIcon.swift`.

Account uses a bounded width/height range, a scrollable explanation/status body
and a separate adaptive native-action footer. Decoration contracts first at
short heights; longer action labels stack through one layout, not duplicated
button trees. Authentication predicates, stable identifiers, keyboard
cancellation, dismissal protection and explicit Account refresh are unchanged.
The main Scene declares a hidden-title-bar window and unified toolbar. No post-creation
bridge forces titlebar background, opacity or full-size content geometry, and
normal app activation is left to LaunchServices/AppKit. Removing those
overrides is not evidence that they previously disabled Liquid Glass.

Apple's [Liquid Glass adoption guidance](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)
supports current-SDK standard SwiftUI/AppKit controls, fewer custom chrome
backgrounds, safe areas and preference/resize testing. This is macOS guidance,
not an iOS touch-target or Dynamic Type score. The deployed app's Mach-O metadata
records SDK 27 and minimum macOS 14; a lower deployment target is not an old-SDK
appearance opt-out. No sampled toolbar tint or additional decorative Glass is
used: the system compositor owns the backdrop. Actual artwork-dependent tint,
modern rendering and constrained-window toolbar placement remain live gates.

| Role | Rule |
| --- | --- |
| Body text / separators | native primary/secondary / Divider |
| Toolbar/status | system primary/secondary; no forced overlay color scheme |
| Controls | native system accent; real available Glass, older material fallback |
| Typography | SF system fonts and symbols; large feature title, native body/section hierarchy |
| Spacing | 4 pt base; 30 pt body inset; 12-24 pt groups; toolbar geometry owned by macOS |
| Entries | 64 pt original icon crops; adaptive 340 pt minimum width |
| Detail | edge-to-edge original imagery, followed by readable ordered evidence |
| Motion | no nonessential animation/autoplay; reduced motion loses no information |

## Original imagery and licensing

Primary 2048 x 1152 scenes (sunset cliff harbor/ship, textured planetary vista/explorer, alpine lake/forest) are original authored CoreGraphics/ImageIO illustrations. `tools/RenderOriginalArt.swift` reproduces them. Secondary desert/forest/ocean worlds have original SVG source generated with Python's standard library and rasterized via native WebKit.

All are **stylized fixture placeholders, not game screenshots or real covers**. No external images, account data, paid assets, trademarks or AI-image service was used. Sources/provenance and original PNGs are GPL-3.0-only. Production must use properly sourced title-specific catalog art with an explicit rights/caching policy.

JPEG derivatives are embedded as data URIs in SVGs, deduplicated per scene, with a strict 10 MB per-screen limit. Original high-resolution PNG resources remain in the app; vectors/text and image crops remain editable in mockups.

## Evidence boundaries and revision history

[Nine v0.2 SVGs](design/README.md) preserve the original editable immersive
composition and the now-superseded custom navigation concept. They are not proof
of the newer system toolbar or live system refraction. In-process AppKit exports
render only the fixture's own NSView hierarchy; compositor/backdrop effects may
be absent. They prove native layout/resource rendering, not live Glass fidelity.

The latest header source follows an explicitly authorized historical private
Apple Games reference that was actually inspected. A fresh single-window capture
attempt failed; an alternative stopped at a false existing-permission preflight,
without requesting permission or capturing. No fresh reference was obtained or
published. The historical image and its account/game content remain private.

[v0.1 SVG archive](design/archive/v0.1/README.md) is explicitly superseded and not user-approved. Its earlier Figma vector import/inspection must not be presented as approval of the revised design. Repo sources/generators remain authoritative. [v0.2 Figma](https://www.figma.com/design/5iQu716UFImHjRxJkf0t8V?node-id=3-115) has nine successful editable imports with Library/Discover render inspection; import flattens some gradients/rounded-image fidelity and does not prove system Glass. [FigJam](https://www.figma.com/board/3MejlFaXHkogmJ3J5k79Gw) is proposed UX; detailed status is in the [mockup index](design/README.md).

Command-1/2/3, Command-F, native Settings and Escape cancellation remain. Decorative images are hidden from VoiceOver; action labels disclose simulations. Full VoiceOver/focus-return, live compositor, both-appearance, reduced-preference, contrast, resize and localization/RTL coverage remain release gates. See [actual build/check evidence](docs/VERIFICATION.md).
