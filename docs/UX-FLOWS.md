# UX screens and state flows

**Full consumer journey specification, not a claim that every step works.**
The default native development app has real bounded account/catalog/registry and
selected-folder inspection clients; [current integration evidence](NATIVE-INTEGRATION.md)
distinguishes those from unfinished inventory/install/play gates. The original
offline `--fixture` preview labels simulated actions explicitly and never claims
real Microsoft access or compatibility.

## Navigation and search

One native Mac window with full-width system toolbar chrome, native traffic lights and no visible app title. Library / Discover / Downloads and compact stock search share the principal toolbar group; Account stays separately trailing. The older floating-capsule mock direction is superseded. Original artwork extends beneath system chrome, without custom tint or decorative glass; whole-toolbar placement/tint still awaits safe live visual confirmation. Library is the proposed first screen: artwork-led focused-game area, compact Continue Playing, then Your Games/count/sort-filter and adaptive horizontal square-icon entries with separate access/compatibility text and contextual action. Discover has immersive feature/browse/shelves; detail imagery is edge-to-edge. Search is scoped to the current tab; Downloads uses a queue, not catalog search. Command-1/2/3 navigate and Command-F focuses search. Native Settings has account/storage, declared runtime configuration and Advanced diagnostics. Back from a detail sheet restores selection and scroll position. No persistent sidebar, Friends or Arcade destination.

[Editable FigJam flow](https://www.figma.com/board/3MejlFaXHkogmJ3J5k79Gw) and [latest v0.2 Figma mockups](https://www.figma.com/design/5iQu716UFImHjRxJkf0t8V?node-id=3-115) are proposed UX artifacts, not observed API behavior or exact system compositor effects.

| Screen | Primary content/action | Distinct states and recovery |
| --- | --- | --- |
| Welcome | Explain legitimate access and runtime limitations; Connect account | Signed out, browser handoff, awaiting approval, cancelled, expired, denied, unavailable. Cancel returns to Welcome; retry creates a new request and never reuses a cancelled token flow. Preview has only "Simulate connection". |
| Library | Continue Playing plus game shelf; access filter and scoped search | Loading, complete, truly empty, no search matches, partial, stale, offline cache, failed inventory. "Try refresh" cannot relabel partial results complete; no cache + failure is an error, not zero games. |
| Discover/Search | Original artwork-led selection; "Not your library" scope note | Catalog loading, unavailable, no matches, edition variants. Discover results may show "No access" and never silently become library items. No purchase CTA in v1. |
| Detail | Artwork, description, four facet rows, edition/language and evidence disclosure | Purchased/subscription/none/unknown independent of downloadable/blocked/unknown; verified/experimental/unsupported/unknown independent of installed/not installed/updating/broken. One reasoned primary action; blocked states explain next safe step. |
| Install sheet | Pinned package plan, destination, storage math, runtime pair; confirm | Planning, ready, insufficient space, changed plan, expired authorization, cancelled. Changing edition/destination invalidates the plan and requests a new one; Escape leaves no job. Experimental requires consent. |
| Downloads | Ordered durable jobs, phase/progress and contextual controls | Queued/downloading/paused/verifying/extracting/committing/completed/cancelling/cancelled/recoverable failure/permanent failure. Retry resumes only verified bytes; integrity error triggers safe re-download or re-plan. |
| Installed detail | Launch, version, update availability | Access revoked, runtime mismatch, missing files, unsupported current OS and offline denial disable launch with reasons. Launch error remains in app with diagnostics; no false "Playing" from exit 0. |
| Settings | Account, destination, safe updates | Disconnect confirms impact on jobs; storage picker checks access; diagnostics explicitly advanced/redacted. License and distribution details await decision. |

## Critical paths

**Declared runtime configuration:** Settings -> choose GPTK3, GPTK4,
legitimately user-installed CrossOver or standalone/source-built Wine ->
optionally declare separate provider/Wine/graphics metadata -> request a fresh
isolated plan or cancel. Initial selection is empty, not the external GPTK4
trial default. Blank versions/hashes remain unknown. Changing any component
clears previous planning evidence. A valid plan still says not inspected,
device preflight not performed, no game verified and Play unavailable; it
creates no prefix and touches no bottles/saves. Unsupported older engine,
invalid response, timeout and cancellation are explicit states. Fixture
Settings share the declarations but keep the planning action disabled.

**Connection:** Welcome -> connect(request ID) -> approved callback -> validated credentials in Keychain -> inventory snapshot. Cancellation from any intermediate state -> signed out. A "login successful" string without tokens -> explicit authentication failure.

**Inventory:** snapshot loading -> complete/partial + time/source -> cached offline if necessary. Purchase is distinct from time-bounded subscription. Play history is only an enrichment source. Unknown access remains unverified; expiry never becomes purchase. A refresh changes facet values but does not erase installation/save records.

**Install:** select exact edition -> evaluate four facets -> fetch authoritative plan -> recheck capacity and consent -> enqueue by idempotency key -> download -> verify -> extract to staging -> atomically register -> ready. Dismissal before confirmation creates no job. Cancellation after confirmation waits for backend acknowledgment; UI shows Cancelling, not instant fictional success.

**Reconnect:** connection lost -> preserve last known job rows with "Status reconnecting" -> request sequence after last applied event -> replay events, or replace with snapshot at a known watermark if retention expired. Never add completed bytes across duplicate events. Terminal job states cannot regress.

**Update:** fetch new immutable package/runtime pair -> preserve existing runnable registry entry -> stage/verify -> atomic promote -> retain rollback according to storage policy. If pre-promotion failure, current version still runs. Save location is separate; incompatible save formats require title-specific warning, not an unconditional rollback promise.

**Removal:** inspect managed paths -> confirm game-content removal -> remove safe manifest-owned content -> registry tombstone. Preserve saves by default. No recursive removal based on a display title or unvalidated path.

**Selected existing folder:** explicitly choose one exact directory in the
native folder picker (aliases not implicitly resolved) -> bounded read-only
streaming-marker metadata -> show selected folder and observed header version,
with unknown retail identity, game-file integrity, access and compatibility.
This result is outside the registered Library and cannot enable Play. Missing,
aliased or malformed markers are visible errors; no scan, adoption, registration
or file write is performed. Cancelling the picker makes no request.

**Rapid scoped search:** one active catalog request plus the latest queued
query/market/language; replace queued intermediate edits rather than starting
every debounce result. Stop drops unsent work and fences active results without
claiming HTTP cancellation. Source-level failures remain recoverable catalog
errors; valid all-failure pages retain visible failures and continuation.

## Status copy and independent evidence

The live toolbar, Account sheet, Settings and Library share freshness-aware
account presentation. HELLO means the development engine is connected, not
that account status was checked. A failed status read can retain the last safe
snapshot for cancellation/recovery fences, but displays "Account status needs
checking" without a saved-profile badge or current-expiry/disconnect advice.
Only a fresh credential result restores "Microsoft sign-in saved"; PC ownership,
installation and play remain separate unavailable evidence.

A pending flow is labelled "Sign-in pending", not proof that a provider window
opened or a particular MFA/passkey step is required. An unreadable pending
outcome stays pending for cancellation/dismissal protection and explicitly
requires a status check; it is never assumed completed or cancelled. Known
failed/cancelled flow results retain their existing static diagnostics.

"Purchased" means purchase entitlement evidence, not "found in catalog". "Included with subscription" carries checked time and expiry when available. "Access unverified" is not an error-free fallback. "Download unavailable" states the reason (PC package absent, market, architecture, access, API or unknown). "Verified on [OS/runtime]" must match current fingerprint. "Experimental" explains what is untested. "Unsupported" is not equivalent to "not owned".

Detail presents access -> downloadability -> compatibility -> local install, then a disclosure of provenance/time/fingerprint. Installed state never bypasses revoked access policy. When multiple reasons block an action, present the most actionable primary reason and retain all facets.

## Fixture interactions

The preview has simulated connection/cancellation, searchable Library/Discover, detail/installation sheets, insufficient-space denial, experimental acknowledgment, an in-memory queue with explicit advancement/pause/cancel/retry, and a simulated launch message. Settings inject partial/stale/offline/empty/error snapshots. Nothing persists or contacts an account. Empty, blocked and error illustrations are also covered by editable mockups; production flow gates remain in [requirements](REQUIREMENTS.md).

## Accessible interaction

Focus order follows chrome -> scope/search -> content -> detail action. Sheets use native controls with cancel/default actions, readable wrapped errors and no required gestures. Decorative art is hidden from VoiceOver; game buttons combine textual evidence. No autoplay art, parallax or progress animation; reduce-motion therefore loses no content. Reduced-transparency mode uses an opaque system window background. Search/tab labels and states must be localized before release; current preview is English-only.
