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

**S3/S5/S6 native operations:** preserve the Library's artwork-led Installed /
Continue Playing / Your PC games order. Install on an uninstalled PC tile opens
a protected native sheet with its title, exact destination, available storage
and honest unknown-size copy. Installation progress is a flat real-byte/phase
view in Library and Downloads, with Cancel and contextual recovery/log actions.
Installed row menus group Check for update / Repair, nondestructive Remove from
list, and separated confirmed Uninstall. The destructive confirmation explicitly
states save preservation; failed preservation never looks like success.
Account distinguishes game-service sign-in from library sign-in, using native
labels/buttons and no credential transfer. Existing semantic colors, SF symbols,
system text, keyboard defaults/cancellation and resize rules apply. Child
buttons retain their own accessibility identifiers rather than inheriting a
whole-section identifier. No additional navigation, sidebar or dashboard is
introduced. The source and signed package are admitted and installed; separate
owner live acceptance is partial. The owner verified child identifiers, the
Installed menu, Repair consent destination/free-space/unknown-size copy and the
code-11 sign-in-required failure with no registry change. No app defect was found in
those flows. Further operation acceptance awaits user-only Keychain approvals.

## Actual native implementation

**S4 PC Library (admitted and installed `7ec1daa`):** the existing native Library retains Continue Playing
and Installed above a distinct Your PC games shelf. Signed out, one native
unavailable-content prompt offers Sign in, Browse games and Recent activity.
The sign-in sheet shows Microsoft's short-lived code, opens the exact Microsoft
verification link and offers Cancel. Signed in, a restrained header/count and stock
Refresh/Sign out controls lead an adaptive artwork/title grid using the existing
catalog-art component and geometry. Exact imported StoreId matches reuse the
same Play/retry/log controls and one-session guard. Other rows say Not installed,
not Install. A quiet excluded-game count and last-updated date describe the
complete filtered account collection; failed refresh retains only the previous
complete shelf with a clear stale notice. Main search filters this PC shelf;
Recent activity keeps its separate scope. This is a bounded adaptation of the
approved Figma Library hierarchy/native tokens, not a new UI world, invented
owned shelf or fixture source. Root separately closed live acceptance after
user-completed device-code sign-in: 13 PC games with real Store box art,
Hogwarts matched to Installed with shared Play, and Refresh/Sign out visible.
This does not certify parity with every Windows Xbox Owned-view entry or
complete accessibility coverage. The owned-view comparison remains open;
the section-identifier follow-up was fixed in S3/S5/S6 and independently
verified live by the owner.

**S1 installed Library refinement (admitted shipping `e401464`):** local tile art uses
Square480, Square150, then StoreLogo from the imported folder's ShellVisuals,
with the existing 60-point square geometry and system-symbol fallback.
Continue Playing appears above Installed only for the newest recorded
Xodus-launched imported game whose folder/script are available. Its splash
(tile fallback) leads a native 12-point-radius hero; title, optional publisher,
relative last-played date and the shared Play control sit on system material
below the image so contrast is independent of the artwork. This preserves the
approved Figma Library's artwork-first hierarchy and native composition without
copying its invented shelves, ownership labels, artwork or custom toolbar.
The hero and list share one process state/error/one-session guard. Art is
decorative; hero content and title-specific controls remain independently
accessible. No motion, personal-history read or network artwork request is
added. Missing art is silent; session-history save failure is a quiet
product message and never prevents play/termination state updates.
Source, neutral/native layout and installed-byte/signature/startup qualification
passed. Root separately closed the live gate using its already-approved native
ScreenCaptureKit observer of the installed app: actual Hogwarts tile art and,
after a Root-launched session, the real splash, title, publisher and relative
last-played date were visible. The test session ended by SIGTERM; shared Try
again and Show log were visible on the hero and row. This is bounded live
evidence, not a claim of natural-exit, complete accessibility or compositor
certification.

**Initial installed-game Play (admitted at `0926414`):** the non-activity Library begins with
an Installed section, separate from the unchanged owned-PC unavailable state.
User-imported entries use their config display name and a restrained system
gamecontroller icon, with native Play and list-only Remove actions. No artwork
request, ownership badge, mock shelf or game count is introduced. The empty
section has one short explanation and Import installed Xbox game. Two native
file panels select the installed folder and its executable working launch
script; cancellation changes nothing. Launching/Playing replace the Play label
for the one active session; other Play buttons are disabled. Nonzero exit shows
one plain error and Try again. Native button focus, title-specific accessibility
labels and `xodus.installed.*` identifiers preserve keyboard/VoiceOver access.
Quit leaves the game running; Remove keeps game files, launch script and saves.
This local list is not an ownership or engine registry claim. Main Library
still never reads TitleHub history; Recent activity remains separate.
Source/native-layout checks and installed-byte/signature/startup verification
passed. No screenshot, actual Import/Play interaction or live gameplay was used
for admission or deployment; those outcomes are not implied by neutral checks.

**User-directed Library semantic correction (historical unavailable state):** Library is the
default. Before S4's account-bound collection/PC join, it used one stock native
empty state, “Your PC library isn't available yet” / “Xodus can't yet verify
which PC games you own,” with real Browse games and Recent activity routes.
No TitleHub image feature, owned game count or fake install/play action was used
to fill this unavailable surface. That history boundary remains in S4. The
Figma Library's purchased/subscription fixture shelf and Apple
Games Continue Playing composition require matching access/installation
evidence; play history cannot fill them.

Recent activity is a separate explicit content scope within Library, with a
native Back to Library action and prominent cross-platform/not-owned-PC copy.
It retains the existing accepted square artwork grid, title-name Store action,
reported-platform filter and account fences, but has no featured history hero.
All history platforms, including PC/mixed, remain outside main PC Library until
ownership and PC Store applicability are independently evidenced. Console-only
activity is shown only here. Search is disabled in main Library and scoped to
the loaded activity window here; it never establishes ownership or Store
mapping. Main Library entry makes no saved-status/history request. Explicit
activity entry reuses the existing bounded deduplicated loader and retained
memory. This correction is independently admitted and installed at consumer
`2d741a7` with the unchanged signed c107 engine. Normal-startup ownership and
installed bytes were confirmed without invoking activity, Account or Store.
The retained native composition has not been visually captured in this pairing;
source/layout checks are not compositor or VoiceOver certification.

**Lean live-data slice:** owned-library enumeration remains unavailable.
The existing native toolbar, deployment target and repository tokens are
unchanged. Discover shows scoped public products and search as artwork-led Store
cards; catalog/access provenance stays in contextual info rather than repeated
ownership caveats. The separate Recent activity scope uses one explicit read
of actual TitleHub history and an adaptive native tile grid.
Reported PC/console/mixed/unknown platform tags and a native platform filter do
not establish Mac compatibility. Search in this scope filters only the loaded
history window. History has no Store mapping, entitlement or installation
evidence; its tiles do not fabricate product-detail or Play actions.
Engine-owned/installed Library enumeration still remains unavailable: the engine's registry response
is a constant empty vector, not an implemented durable registry or Mac scan.
It must not become "no games registered" or an installed-game list; Library
search is disabled. A real, read-only selected-folder marker check remains
visible, separate from retail identity, entitlement, installation and launch.
Product IDs, package metadata, provenance and
selected-folder marker inspection remain available in contextual information
disclosures. Operation-specific failures remain visible and actionable;
retained account snapshots are explicitly unconfirmed, not current saved-state
evidence. Product
detail has one availability line, with independent per-edition evidence in
Catalog info, a compact preferred size and a separate native Done footer.
Unchecked/empty/failed history has one clear state and explicit Account/load or
refresh action. Retained results visibly say they are previously checked;
account/connection changes and explicit Account checks clear personal memory.
Credential-present status carries no user identity binding, so a fresh status
cannot establish that earlier personal history belongs to the current account.
No Account check automatically rereads history.
Selected-folder inspection is secondary under Library details. Discover places
results directly after one scoped heading and any actual partial/failure notice.
Account stays
in the toolbar, and its cancellation, refresh and credential gates are
unchanged. No Home shelves, invented installed games, new framework or
speculative navigation API is introduced.

**Recent-title Store action:** a stock bordered "Find in Store" button accompanies
the activity tile entries without changing their artwork geometry
or tokens. The button has native keyboard focus/activation and a title-specific
VoiceOver label; containing accessibility groups keep the action independently
reachable. Only this explicit action routes the title name into the existing
Discover search. It does not establish a product/edition mapping or select a
result. The user chooses among catalog candidates, with the existing partial,
empty and error presentation; history and account state remain separate.

**Production hardening:** the shipping/live path no longer uses the invented
harbor/orbit promotional hero or game poster in Account. Title-specific artwork
comes only from normalized real Microsoft metadata, not bundled covers, invented
illustrations or an image-generation service. The shared native loader admits
only the exact Store CDN, disables redirects/auth/cookies and bounds each fetch
to 10 seconds, 8 MiB and 16 megapixels before decoding. Its decoded thumbnail
cache is memory-only. Missing/rejected/unqueried metadata and fetch failures
remain distinct; a failed fetch never changes metadata to "absent."
Setup/empty/error views keep semantic native window backgrounds. Fixture
illustrations remain only in the nonshipping preview source/resource set.
Remote metadata references are not a general redistribution/license grant;
distribution rights remain a separate release question.

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

The live development shell inherits this world without copying fixture game names or covers. It uses a labelled original landscape, a separate native account sheet and centered unavailable/empty states. The same scoped `NSSearchField` supplies toolbar search in live and fixture views: system bezel, search/cancel controls, semantic appearance and the existing field editor/focus binding. Empty unfocused search occupies 32 pt; editing, Command-F or nonempty text expands it to 220 pt. Downloads retains disabled search, and live Library eligibility rules remain unchanged. There is no duplicate hero search, wrapper icon, forced dark scheme or custom capsule. Fixture/development notices remain inside content rather than an opaque strip above the hero. Checked products use real BoxArt/poster references, with SF-symbol fallbacks only
for actual missing/rejected/unqueried or failed images. Product detail uses an
actual hero-role image when supplied, plus its real cover. TitleHub tile art
keeps its own aspect rather than being relabelled as SuperHeroArt. Four-facet detail does not turn catalog presence or saved sign-in into ownership. The original orbital-doorway app icon is reproducible with `tools/RenderAppIcon.swift`.

Account uses a bounded width/height range, a scrollable explanation/status body
and a separate adaptive native-action footer. Decoration contracts first at
short heights; longer action labels stack through one layout, not duplicated
button trees. The live text-only sheet prefers a compact 280 pt height instead
of the illustrated fixture's 620 pt height; long failures and expanded Account
info scroll without moving the action footer. Authentication predicates, stable identifiers, keyboard
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
| Entries | real Store covers fitted without branding crop / square history tiles; adaptive native grid |
| Detail | actual catalog hero/cover, followed by readable ordered evidence and a fixed Done footer |
| Motion | no nonessential animation/autoplay; reduced motion loses no information |

## Original imagery and licensing

Runtime Settings reuse the existing grouped native Form, standard Picker,
TextField, DisclosureGroup and buttons; no new navigation, decorative material
or custom control chrome. CrossOver is first-release supported; only a verified
official app observation defaults an unset profile. All alternatives are
Experimental with visible acknowledgement, outside the advanced disclosure.
Dependency status and its native check/official information actions stay in
Settings, rather than repeating a runtime wall in Library and Account. Dependency
actions remain visible; only explanatory/experimental copy collapses. Controls adapt to
constrained widths; checking/absent/unverified states do not fabricate readiness
or disable unrelated catalog/account actions. Advanced component
declarations remain separate from the primary provider choice, and configuration
planning never advertises installation or verified gameplay. Fixture mode
disables planning. Detached controls/layout checks are not a live visual,
VoiceOver or compositor-conformance claim.

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
