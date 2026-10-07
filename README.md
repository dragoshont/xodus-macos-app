# Xodus for Mac

A native Mac launcher in development for legitimately entitled Xbox PC games, integrating with the Xodus management engine.

**Current status: native development app, not a complete game launcher.** The default SwiftUI/AppKit app has a real bounded management client, isolated Microsoft Store sign-in integration, source-backed PC Game Pass discovery and Microsoft Store network search, edition detail and activity. A native folder picker also supports a read-only marker check in one explicitly selected game folder; observed header identifiers never become retail identity, registration or permission to launch. A packaged development build includes its matching engine and connects without Terminal setup; negotiated capabilities determine which actions work. Search coverage is explicitly partial, and public results never establish ownership. The admitted f30/d00 pair confirmed saved credentials after the user's native Keychain approval and completed one Halo authenticated read with `verified: true`; no repeat verification or ownership inference was made. S4 now has a live-accepted account-bound PC Library. Game-service sign-in, installation, repair and uninstall are implemented and installed, with owner live acceptance pending. Broader owned-PC coverage comparison, an engine-backed installed-game registry and general gameplay certification remain gaps. Saved sign-in alone is **not** proof of PC ownership or package access.

The original offline demonstration is **nonshipping only**. `XODUS_SHIPPING=1`
compiles out its views, invented state, artwork, resources and check/export
entrypoints. Shipping screens use native setup/empty/loading/error states and
actual public product data, not synthetic game illustrations. See
[native integration status and evidence](docs/NATIVE-INTEGRATION.md).

**S3/S5/S6 (`1463cdb`, admitted and installed; live acceptance pending):** the account area
adds explicit game-service sign-in/status, separate from PC-library credentials.
PC Library games offer Install with native destination/free-space consent.
Downloads shows script-reported bytes and phases; Cancel signals only the
app-owned install process and waits for its result. Installed entries offer
Check for update / Repair, confirmed Uninstall, and the unchanged list-only
removal. Script success still must pass the same local config/launcher validation
and private registry save as Import. Games being changed cannot be played; one
mutation runs at a time, and normal Quit waits for completion or cancellation.
Private scripts, gameplay credentials, save preservation and engine behavior
remain owned outside this public repository. No private implementation is
imported and the signed C8 engine is unchanged.
[Exact-source CI passed](https://github.com/dragoshont/xodus-macos-app/actions/runs/37640727574),
along with 684 native checks, including 77 game-operation checks. The owner
independently admitted the signed UI-only package and freshly confirmed no game
was running before authorizing normal Quit/replacement. All 21 installed files
and strict signatures match admission. A full S4 rollback is retained; the
profile was left untouched and the private installed list remained byte-identical through one
ordinary Library reopen. No game operation or sign-in was automated by the app
implementation/deployment lane. Separate owner live acceptance remains pending.

The owner has now verified child accessibility identifiers, Installed menu
actions, the Repair consent sheet's destination/free space/copy, and a real
Repair failure with code 11 and no registry change. No app defect was found in
those flows. Further live acceptance is held on user-only Keychain approvals;
successful Install, Repair, Uninstall and Play on this build are not yet claimed.

**S4 PC Library (`7ec1daa`, admitted, installed and live-accepted):** a separate native
Microsoft device-code sign-in reads the account's complete paged collection,
then joins active, non-trial Game entries to exact Store products declaring
`Windows.Desktop`. The Your PC games shelf never comes from Xbox activity or
Game Pass discovery. Imported StoreId matches share the existing Play action;
other games say Not installed. Refresh tokens alone use an app-owned Keychain
item; access/Xbox tokens and the library remain in memory. Entry checks saved
sign-in presence without reading credentials or automatically querying.
Partial/failed refreshes are explicit and cannot become an empty library.
Installed and Continue Playing remain above the shelf.
[Exact-source CI passed](https://github.com/dragoshont/xodus-macos-app/actions/runs/37617059339);
the independently admitted signed package preserves C8 byte-for-byte. Normal
Quit/replacement preserved the full S1 rollback, profile and private installed
list; all 21 installed files and strict signatures matched admission. One
ordinary Library startup was left open. Root separately confirmed user-completed
in-app sign-in and 13 PC games with real Store art; Hogwarts matched Installed
with the shared Play control already verified in S1/S2. Root closed S4.
Those observations do not come from neutral or deployment checks. The owned-view
coverage comparison remains open in the owner's spec. The section-identifier
follow-up is addressed in the S3/S5/S6 source above, and the owner has verified
the child identifiers on the installed build. This is not complete accessibility
certification. S4 itself does not add installation, entitlement inference from
history, or a backend/engine change.

**Installed-game Play (introduced at `0926414`, retained in shipping `1463cdb`):** main Library has an **Installed** section
above the separate account-bound PC shelf/sign-in prompt. Import an already-installed Xbox
game folder, then explicitly select its executable Xodus launch script. The app
reads `MicrosoftGame.config` locally and saves only the selected entry in a
private, atomic local list. Play runs `/bin/bash <script> <runID>` with a minimal
environment. Only one game session runs at a time; Launching becomes Playing
while the script remains alive, and its exit ends the session. A failed exit
shows its code and Try again. Quit does not stop the game. Remove from list deletes only
the list entry, never the game, launch script or saves. These local imports are
**Installed**, not Owned, and do not establish Store availability or entitlement.
No backend, contract or signed engine change accompanies this interface.
Hogwarts Legacy's live test is separately user-controlled; neutral checks never
launch a real game.

**S1 admitted, installed and live-accepted:** imported tiles use bounded local PNG/JPEG art from
MicrosoftGame.config. The newest recorded Xodus-launched imported game supplies
a Continue Playing splash card, publisher and relative last-played date, sharing
the list's Play state. Session start/duration stay in the private local list;
old entries still load. Nonzero sessions offer Show log only for an existing
generated-session stderr file. This is not Xbox activity, ownership or network
artwork. [Exact-source CI passed](https://github.com/dragoshont/xodus-macos-app/actions/runs/37610002150).
Root independently admitted the matching package and confirmed the game had
ended before normal Quit/replacement. All 21 installed files and strict
app/helper/engine signatures matched admission, with C8 unchanged. Full 092
rollback, profile and installed-list bytes/permissions were preserved. One
ordinary Library startup was left open; no Import or Play was automated by the
app implementation/deployment lane. Root subsequently observed actual Hogwarts
tile artwork and, after its own post-install Play session, the real splash,
publisher, relative last-played date and shared retry/Show log actions.
Session history persisted with 0600 permissions. Root closed S1 with no defect;
this separate live evidence is not inferred from neutral or package checks.

The initial Play slice's exact-source [CI passed](https://github.com/dragoshont/xodus-macos-app/actions/runs/37603065132).
The independently admitted package was installed after normal Quit, preserving
a complete working 2d rollback, the profile and older rollbacks. All 21 installed
files and app/helper/engine signatures matched admission. The exact signed C8
engine is unchanged. One ordinary main-Library startup was left open; no Import,
Play or real-game launch was automated, and no screenshot or gameplay proof is
claimed.

**Preserved Library history boundary (first admitted at `2d741a7`):** before S4,
the owned-PC Library showed an unavailable state rather than guessing which
games you own. S4 replaces that state only with explicit account-bound
collection/PC-package evidence. Main Library still does not display TitleHub
history as your games, a featured owned title or a PC Store shelf, and entering
main Library makes no saved-status or history request. **Browse games** opens
Discover; **Recent activity** explicitly opens a separate in-Library scope.
That scope prominently identifies cross-platform play history, not your owned
PC library. Even a reported PC/mixed tag does not establish Store availability
or entitlement; console history appears only in activity. Activity search and
the reported-platform filter apply only to its loaded partial window.

Explicit activity entry uses the existing bounded saved-status-then-history
loader: fresh credential-present status is reused, ordinary view rebuilds and
return visits do not poll, and failures require manual retry. No automatic
login, persisted history or title-to-Store mapping is introduced. Consumer
`2d741a7` passed exact-source CI and independent source/package admission and was
installed with the unchanged signed c107 engine. One ordinary startup left the
same corrected shipping process running in main Library. All 21 installed files
and its single parent-owned engine matched admission; no helper was running.
No activity, Account or Store action was invoked for proof. Bounded aggregate
observation found no recent-list publication or image-decode events; this is
not API-trace or visual evidence, and anonymous startup catalog search remains
unchanged. Source and neutral checks establish the main-Library data boundary.
Normal Quit preserved the complete working 0a bundle, older rollbacks and profile.
The historical deployment evidence below describes the earlier presentation.
The earlier controlled
113be57/c1073100 pair was admitted and installed: one foreground check confirmed
saved sign-in, and one actual TitleHub read returned a partial 20-title window
with 20 available artwork entries and none rejected. All 20 preload references
succeeded, with zero failures; references may share cached images, so this is
not a claim of 20 unique HTTP requests. A private actual Library image was
visually confirmed with real title artwork and a featured tile. Real Store
covers and hero images were separately confirmed in Discover and Product.
Own-view evidence is not compositor or accessibility certification. The
reopened shipping app had a separate session: the export did not persist or
inject history. That historical export is not proof of the new startup flow.

The prior **0a6dca1/c1073100 shipping pair was admitted and installed**. Its
ordinary foreground startup published one real 20-title recently-played window,
and the same shipping process decoded 12 actual artwork images successfully.
That populated app was left running, with one matching engine and no sign-in
helper. No private exporter, additional personal request or reopen was used.
These are aggregate publication/decode observations, not a claim that every
title has a distinct fetched image or that recent activity proves ownership.
Recent entries now have a native **Find in Store** action. Only invoking it
uses the title name to search Discover; you choose among catalog candidates.
It does not map history to a Store product, establish access or enable play.
The routing/selection behavior was qualified with neutral tests and exact CI;
no personal-title Store query was automated during deployment.

Engine-owned/installed Library enumeration remains unavailable: the installed snapshot is a constant empty
response, not a durable registry or scan of this Mac. It never proves that no
games are installed. A selected-folder marker check is separate from ownership,
game-file integrity and permission to play. Technical metadata stays in
contextual information disclosures. No Install action is offered. The separate
local Installed list above enables Play only through an explicitly imported
working launch script, not through the engine's empty registry.

![Original Library concept](design/previews/library.png)

## Explore the foundation

| Artifact | Purpose |
| --- | --- |
| [Product](PRODUCT.md) | Audience, scope, principles and undecided product choices |
| [Design](DESIGN.md) | Native visual direction, tokens, interaction and original mockups |
| [Requirements](docs/REQUIREMENTS.md) | Traceable requirements and measurable acceptance criteria |
| [UX flows](docs/UX-FLOWS.md) | Screens, cancellation, loading, degraded and recovery states |
| [Architecture](docs/ARCHITECTURE.md) | SwiftUI/AppKit boundary, Rust adapter and trust model |
| [Backend contract](docs/BACKEND-CONTRACT.md) | Pinned scoped management protocol and future lifecycle requirements |
| [Runtime providers](docs/RUNTIME-PROVIDERS.md) | Four declared presets and separately versioned, configuration-only planning |
| [Native integration](docs/NATIVE-INTEGRATION.md) | Actual native client, developer app bundle, limitations and producer pin |
| [Research and decisions](docs/RESEARCH.md) | Evidence, leads, uncertainties and decision register |
| [Milestones](docs/MILESTONES.md) | Release gates; prototype is not a production milestone |
| [Implementation ledger](docs/IMPLEMENTATION-LEDGER.md) | Durable v1 work IDs, actual-vs-fixture status, dependencies, evidence and blockers |
| [Editable mockups](design/README.md) | Original SVG screens, shared tokens and reproduction |

Design collaboration: [nine editable v0.2 Figma mockups](https://www.figma.com/design/5iQu716UFImHjRxJkf0t8V?node-id=3-115) and [editable FigJam UX flow](https://www.figma.com/board/3MejlFaXHkogmJ3J5k79Gw). Revised Library/Discover renders were inspected; [import status](design/README.md) records static SVG fidelity limits and superseded v0.1. These are proposed designs, not implemented APIs, exact compositor effects or a wired Figma prototype.

## Run the native development app

On an Apple Silicon Mac with the **Xcode/SDK 27 or newer** toolchain
(tested with Apple Command Line Tools, Swift 6.4 and SDK 27.0):

```sh
swift run XodusFixtureChecks
swift run XodusPreview
```

The historical SwiftPM executable name remains `XodusPreview`; its default is now the live development shell, **not simulated gameplay**. Source-only development can select a trusted engine in Advanced Settings or explicitly use `XODUS_BACKEND_PATH`. A packaged build uses its included engine automatically; a missing/nonexecutable included engine shows an actionable error rather than silently using a saved external build or convincing fixtures. There is no interactive-CLI scraping or arbitrary Wine picker. The main launcher never receives credentials; the isolated Swift authentication host handles only its private memory-only handoff, not credential storage or cryptography.

Build a controlled local `.app` only after independent source and sealed-input
approval; placeholders below are required operator pins, not values to guess:

```sh
sh tools/build_app.sh /absolute/reviewed/engine UNSIGNED_SHA BYTES PROVENANCE_SHA PROVENANCE_BYTES APPROVED_APP_COMMIT APPROVED_APP_TREE /absolute/owned/output
```

The packager verifies independently supplied unsigned CLI/provenance hashes,
sizes, exact approved producer source/tree, release profile and feature sets. It creates
a new stage, separately signs engine/helper, generates stage-only compiled
pair pins and then builds the shipping launcher. The final helper receipt and
signed identities must match those compiler inputs. No engine override, picker,
remembered path or runtime JSON can grant shipping approval. An unpaired shipping
build fails before any engine process. The prior `dist/Xodus.app` is never moved
or replaced. This source tooling is not an executed package, notarization,
distribution attestation or successful human login; deployment/launch require
separate approval. See [controlled pair admission](docs/SHIPPING-ADMISSION.md).

The proposed deployment baseline is **macOS 14**, not a user-approved support commitment. The shared native toolbar groups Library / Discover / Downloads with compact stock `NSSearchField` search: real `.tabs` on macOS 27+, segmented fallback on 14-26. Search expands for editing, Command-F or a retained query; Account stays separate at the trailing edge. The Scene hides the visible title while retaining native traffic lights and app identity. Live title art uses only actual normalized Microsoft metadata URLs through a
bounded memory-only native loader; proprietary covers are not bundled or
committed. Empty/error states keep semantic native backgrounds. Account content scrolls independently of its adaptive action footer, and normal activation remains AppKit-owned. Source/headless checks alone do not establish deployment or visual conformance; the controlled pair's actual own-view confirmation is recorded separately.

**Official CrossOver, installed separately, is the first-release dependency.**
The app checks only standard app locations, bounded metadata and a fixed
Apple-anchored CodeWeavers signature requirement. A verified installation
defaults a new/unset profile; explicit choices are preserved. Missing/unverified
CrossOver blocks first-release gameplay setup, not public browsing or Microsoft
sign-in. Wine/GPTK and custom graphics remain **Experimental**, with explicit
acknowledgement reset by configuration or observed installation changes.
See [runtime policy and scoped trust source](docs/RUNTIME-PROVIDERS.md).

Wine/graphics versions and hashes remain independent declarations. The separate
bounded `runtime-plan` validates configuration only; it never executes CrossOver,
checks a license, creates a prefix, migrates saves or enables Play. A verified
app signature is not entitlement or game compatibility. The nonshipping fixture
Settings cannot inspect CrossOver or start planning. The controlled development
sign-in result does not qualify this runtime policy for gameplay or distribution.

`XodusAuthHost` implements AppKit/WebKit window ownership and a strict private,
anonymous-channel protocol. Its exact seven-string legacy handoff remains
memory-only; Rust retains proof/SOAP processing and credential commit. Neutral
WebKit and channel checks do not contact Microsoft. The controlled human flow
now reaches saved sign-in, including after restart. Actual bounded provider
reads are recorded separately from neutral checks; passkey coverage and full
owned-library enumeration remain unqualified.

**Visual revision v0.2 supersedes the unapproved flat v0.1 concepts.** SVGs describe editable layout and intended glass placement, not live compositor refraction. Native own-view exports also cannot establish backdrop/refraction fidelity; the native implementation, not an SVG blur, owns system Glass.

For the original offline design demonstration:

```sh
swift run XodusPreview --fixture
```

In that nonshipping mode, choose **Library / Discover / Downloads**, search within the current scope, open an invented game, and use **Simulate install** or **Simulate next step**. Fixture Settings inject empty, partial, stale, offline and cancelled-auth scenarios. Simulated jobs exist only in memory and reset on relaunch. Fixture mode never contacts the engine, opens sign-in or writes a game registry. There is no live Settings transition to preview; start it explicitly as a separate nonshipping invocation.

```sh
swift run XodusPreview --self-check
```

Core, presentation and `swift run XodusManagementChecks` are dependency-free executables. Presentation checks also allocate native search controls and lay out synthetic Account content in detached `NSHostingView` instances: no window is shown, no provider is loaded and no backend connects. They do not render or capture an existing app. Management checks use the producer's sanitized fixtures plus real mock child processes to exercise negotiation, framing, EOF/timeouts/exit failures, request correlation and activity reconciliation. They do not sign in or approve Keychain access. Command Line Tools do not include XCTest/Swift Testing on the tested Mac. [Verification](docs/VERIFICATION.md) records actual evidence separately from future release criteria.

`swift run XodusPreview --live-check` exercises the actual native session coordinator against synthetic subprocesses: expired-profile recovery, permission failures, transient/late-cancel reconciliation and failed-page continuation. It exits before creating a window and performs no Microsoft or Keychain operation.

Native Settings can preview and save a **counts-only diagnostic summary** through
a native file picker. Only the reviewed summary is saved, not raw engine logs,
account identifiers, tokens, URLs or personal paths. Writes are atomic and run
off the main actor; failures remain explicit. Overlapping disconnect/reconnect
operations share bounded shutdown ownership rather than starting another engine
before the old child exits.

`sh tools/check.sh` runs the native/management/nonshipping-fixture/private-host checks,
portable packaging negatives, actual shipping release compilation and separate
shipping XCTest admission checks. The latter require full Xcode's test framework,
not only Command Line Tools; they never become application entrypoints.
The existing GitHub-hosted `xcode-27` job checks actual SDK/runtime versions and
SVG regeneration. A workflow definition is not evidence of a passing revision.

Own-view exports use `--export-preview <directory>` for fixtures or `--export-live <directory>` for a **disconnected**, non-account live shell. They export this app's Library, Discover and Downloads view hierarchy and exit; they do not capture the desktop/other apps or establish Glass-compositor fidelity.

## Boundaries and licensing

The app is standalone: Heroic does not offer a proven shipping new-store plugin API. Existing Xodus runtime service IPC is **not** the management protocol. The scoped adapter does not resolve authoritative PC ownership, safe package installation or the exactly paired Xbox-capable gameplay runtime.

No private runtime source, credentials, real account data, proprietary game covers, Apple assets or paid design assets are included. The original app source, documentation and mockups are licensed **GPL-3.0-only**, by the user's explicit choice; see [LICENSE](LICENSE) and [licensing boundaries](docs/LICENSING.md). Third-party runtime components/assets retain their own licenses. Dependency redistribution, signing/notarization and installer distribution remain pending. This license does not grant rights to Microsoft packages or runtime components.
