# Design system: immersive native Glass, v0.2

## User-directed visual contract

Apple Games for macOS is the **actual composition/layout authority**, not loose inspiration. The user rejected the flat v0.1 interpretation and requested newer Liquid Glass with rounded transparent floating navigation and immersive game imagery. The framework remains native SwiftUI/AppKit: it supports the same modern Mac system Glass without a UIKit rewrite.

Center a fully rounded floating Library / Discover / Downloads capsule **over** full-bleed original art. Put the account control in a separate floating circle at the trailing edge. Keep native traffic lights/titlebar behavior; no opaque full-width segmented header, web sidebar, Xbox-green brand or copied Apple logo/art/source. Feature art reaches behind chrome, and detail art is edge-to-edge.

## Surfaces

**Library (Operate):** original immersive focused-game area, scoped Search, compact Continue Playing, then Your Games/count/filter-sort. Three columns of horizontal square-icon entries at roomy widths, fewer when resized. Title, access, compatibility and contextual View are separate. The compact Library observation remains important, but no longer prohibits the featured imagery explicitly requested by the user.

**Discover (Operate/explore):** immersive original environment, one title/action, empty-query categories and catalog shelf. Typing shows scoped results rather than fake empty-query results. Catalog presence never proves ownership.

**Detail/install/downloads (Operate):** full-bleed detail image, four independent evidence rows and one reasoned action; protected installation sheet with space/experimental consent; flat progress rows and recoverable errors. Artwork never replaces evidence.

## Actual native implementation

`NativeGlass.swift` uses macOS 26+ `glassEffect(.regular.interactive(), in: Capsule())`, `GlassEffectContainer` and `.glassProminent` buttons. `PreviewWindow.swift` sets transparent titlebar, hidden title text and `fullSizeContentView`, retaining native traffic lights. `RootView` extends art through the top safe area.

Floating overlay chrome has a **local dark color scheme and white foreground** for contrast against immersive images, including when offscreen snapshots omit compositor materials. The body remains adaptive light/dark. Reduced transparency uses opaque scheme-appropriate surfaces; older macOS uses normal materials as an explicitly labelled compatibility fallback, not "Liquid Glass." There is no fake CSS glass or private SDK import.

The live development shell inherits this world without copying fixture game names or covers. It uses a labelled original landscape, a separate native account sheet, centered scoped search and centered unavailable/empty states. A native `NSSearchField` supplies the field editor, readable attributed placeholder and keyboard focus over immersive art. Checked real public products use honest native icon placeholders until rights-cleared title artwork exists. Four-facet detail does not turn catalog presence or saved sign-in into ownership. The original orbital-doorway app icon is reproducible with `tools/RenderAppIcon.swift`.

| Role | Rule |
| --- | --- |
| Body text / separators | native primary/secondary / Divider |
| Overlay text | white in locally dark chrome; body appearance unaffected |
| Controls | native system accent; real available Glass, older material fallback |
| Typography | SF system fonts and symbols; large feature title, native body/section hierarchy |
| Spacing | 4 pt base; 30 pt body inset; 12-24 pt groups; floating capsule separate from window edge |
| Entries | 64 pt original icon crops; adaptive 340 pt minimum width |
| Detail | edge-to-edge original imagery, followed by readable ordered evidence |
| Motion | no nonessential animation/autoplay; reduced motion loses no information |

## Original imagery and licensing

Primary 2048 x 1152 scenes (sunset cliff harbor/ship, textured planetary vista/explorer, alpine lake/forest) are original authored CoreGraphics/ImageIO illustrations. `tools/RenderOriginalArt.swift` reproduces them. Secondary desert/forest/ocean worlds have original SVG source generated with Python's standard library and rasterized via native WebKit.

All are **stylized fixture placeholders, not game screenshots or real covers**. No external images, account data, paid assets, trademarks or AI-image service was used. Sources/provenance and original PNGs are GPL-3.0-only. Production must use properly sourced title-specific catalog art with an explicit rights/caching policy.

JPEG derivatives are embedded as data URIs in SVGs, deduplicated per scene, with a strict 10 MB per-screen limit. Original high-resolution PNG resources remain in the app; vectors/text and image crops remain editable in mockups.

## Evidence boundaries and revision history

[Nine active v0.2 SVGs](design/README.md) show the intended visible capsule geometry and immersive composition. They are static layout concepts, **not reproduction/proof of live system refraction**. In-process AppKit exports render only the fixture's own NSView hierarchy; compositor/backdrop effects may be absent. They prove native layout/resource rendering, not live Glass fidelity.

[v0.1 SVG archive](design/archive/v0.1/README.md) is explicitly superseded and not user-approved. Its earlier Figma vector import/inspection must not be presented as approval of the revised design. Repo sources/generators remain authoritative. [v0.2 Figma](https://www.figma.com/design/5iQu716UFImHjRxJkf0t8V?node-id=3-115) has nine successful editable imports with Library/Discover render inspection; import flattens some gradients/rounded-image fidelity and does not prove system Glass. [FigJam](https://www.figma.com/board/3MejlFaXHkogmJ3J5k79Gw) is proposed UX; detailed status is in the [mockup index](design/README.md).

Command-1/2/3, Command-F, native Settings and Escape cancellation remain. Decorative images are hidden from VoiceOver; action labels disclose simulations. Full VoiceOver/focus-return, live compositor, both-appearance, reduced-preference, contrast, resize and localization/RTL coverage remain release gates. See [actual build/check evidence](docs/VERIFICATION.md).
