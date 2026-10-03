# Native management integration

This is implementation work beyond the immutable foundation at `44d7338`. It is **not a consumer-ready game launcher**.

## Implemented client and native surfaces

`Sources/XodusManagement` implements exact protocol 1.0, request IDs, schema validation against the producer's pinned schema, typed capability objects, bounded UTF-8 JSONL and a supervised native `Process`. It never scrapes interactive output or uses runtime-service IPC as management.

Each request is correlated to its expected command-specific result definition. EOF, malformed/truncated/oversized frames, wrong IDs/shapes, unexpected major/minor, timeout and nonzero exit invalidate the connection; exit zero cannot supply a missing result. Output/event buffers and outstanding requests are bounded. stderr is drained and discarded with a byte limit, not retained as diagnostics. Error messages shown by the app are generated locally from validated error codes, not raw upstream text.

Closing the client first closes stdin for owned-child cleanup, waits for the engine to exit and release its state lock, and applies bounded signal escalation to that exact owned process if needed. Reconnect does not race the old process's lock. The app does not stop another runtime or game.

`LiveSession` and the native views implement a real default development shell: account status, explicit sign-in/cancel/logout actions, scoped partial catalog, edition detail, catalog-check cancellation/retry and authoritative activity snapshots. Native sign-in is backend-owned; the Swift app never receives tokens, redirect fragments or raw provider errors. Optional agreed flow metadata is consumed only through the bundled producer schema and negotiated capabilities. New sign-in is always an explicit user action, never startup or a test action.

Anonymous startup does not read the Keychain. Account initially remains unchecked;
opening Account shows that state explicitly, and **Check status** or **Sign in
with Microsoft** initiates the corresponding operation. The original GUI startup
was observed to time out specifically in `auth.status`, despite the equivalent
SSH read failing promptly with `credentialStoreUnavailable`. Removing that
automatic read preserves anonymous browsing without approving any native consent.
The coordinated producer fix also makes management-profile status reads
noninteractive. OSLog records process start, negotiation and the canonical command
name on timeout only; no paths, arguments, IDs, credentials or upstream messages
are logged.

Sign-out clears account-bound UI evidence before the operation and is shown as signed out only after the backend confirms removal. Engine/Keychain errors remain errors. A transport failure invalidates credentials/evidence in the UI rather than silently falling back to invented games.

Discover now requests one bounded public **pcGamePassDiscovery** page at a time from the official Microsoft PC Game Pass feed. Request market/language, cursor and corpus revision remain bound together. Successful public products seed **observedPublicProducts** checked-catalog title search; that search is not full Microsoft Store search or an owned library. Duplicate identities and contradictory product/edition scope are rejected. This public catalog cannot promote entitlement from unknown. Catalog checks are not game downloads; the activity UI names their actual operation.

Each attempted page item is either a product or a visible lookup failure. An
all-failure response remains an error: only command-correlated
`failedDiscoveryData` is retained, validated separately from successful discovery
whose products cannot be empty. No arbitrary error payload or raw upstream message
is displayed. The native request allows 45 seconds around the producer's
30-second whole-page budget; there is no full-feed crawl. Requested locale remains
the cache scope; exact language is preferred, or an explicit same-base neutral
`resolvedLanguage` is shown. Unrelated/regional fallback is rejected.

Activity snapshots fence a bounded set of incoming events until the authoritative
watermark is applied, then replay newer buffered events in order. A gap triggers
a bounded snapshot retry, not a guessed queue state. Failed reconciliation retains
previously verified jobs as non-current and disables cancellation/retry until
the current snapshot is established.

The Library and product detail also consume typed `installed.snapshot` records,
including package identity/version and recorded health. An empty management-only
registry is not evidence that other game folders are absent. Failed status
refreshes show unknown/error instead of retaining a success-shaped empty result.
Public catalog `notInstalled` metadata is not treated as a whole-Mac installation
scan. User-selected, read-only existing-install inspection is the next coordinated
backend contract, not permission for a blanket private-folder scan.

## Producer pin

The current schema pin is `dragoshont/xodus-macos`, branch `dragoshont-xodus-launcher-management`, commit `790f5c40e69570324e7674638d487469a8aa8c8c`. It adds strict failed-page validation to the discovery implementation at `8718dcb3f1a5a573c685d95dc78c8d41e8e0bbed`; the preserved discovery executable is unchanged by the schema-only follow-up.

Canonical committed schema SHA256:

`2ede71d5171cf4dc1659fedfc99187a90d904d9264119a22ee9f94064baef3d2`

Committed LF bytes and all four sanitized fixture hashes were independently verified from immutable public Git objects. A transient GitHub network outage was handled with that exact public-only fallback, not mutable backend source or private data.

`docs/contracts/management-v1.schema.json` is the producer's canonical scoped schema. `tools/sync_contract.py` copies its exact bytes to the Swift resource. `Tests/ManagementChecks/Fixtures` contains its sanitized public positive/negative/evidence fixtures. No private backend source or real account payload was imported. `foundation-v1.schema.json` preserves the original proposal.

The preserved unsigned discovery engine input has SHA256 `14dd06466a201ddb77fe7c2d6f9a57bbbb79788f03413989e5158d9053c864ad`. Local ad-hoc signing during embedding changes the executable bytes; this packaged copy has SHA256 `62cb9564478d2a2bcee472b6f7d6865f5f3007a0314e30c7a06537523820f175`. **Provider consent remains separate from read-only/schema/build verification.** No successful account login is claimed merely because the native UI compiles.

## Developer application

On the isolated Mac:

```sh
sh tools/check.sh
sh tools/build_app.sh
open dist/Xodus.app
```

The `.app` includes a release executable, required SwiftPM resources, original native icon and a development bundle identifier. An optional explicit management-engine argument embeds a matching local development build. Its native auth worker re-executes the same binary and returns its session through a backend-private inherited socket; the app receives status only. It is ad-hoc signed and locally verified, **not notarized or released**. No Wine/runtime payload, real library or credential cache is bundled.

Settings provides a native engine picker, account controls, explicit catalog market/language, advanced public-product lookup and a bounded redacted diagnostic preview. Backend discovery in a developer bundle does not establish signed runtime certification.

Default LaunchServices startup was exercised with `open Xodus.app`, no mode,
backend flag or environment override. After fixing the automatic account read,
the included-engine child survived beyond the original timeout and the normal
Library/Discover/Downloads/Account controls passed bounded Accessibility
interaction. The committed `tools/check_live_ui.applescript` requires the exact
owned PID, bundle identity, non-fixture window and stable native control identifier;
it refuses blind interaction and logs only allowlisted, locally authored labels.
This is not a full VoiceOver or provider-consent test. Missing included engines do not silently select a remembered
developer binary. User-mediated store authentication will use a backend-isolated
launcher Keychain profile, not implicit CLI/private-worker credential import.

`--fixture` opens the separate, labelled original design preview. Switching to it disconnects live work first. Fixture data never populates the live app. `--export-live <directory>` deliberately suppresses backend connection and renders only a disconnected shell, so its images cannot expose account/library content.

## Evidence and still-open gates

At this discovery milestone, `sh tools/check.sh` passed on the Mac: **14 core + 130 management + 24 presentation = 168 checks**, zero failures. The management set includes all 71 positive, eleven negative and four evidence-edge producer frames, typed auth/registry/discovery results, exact all-failure/error separation, locale checks, real mock subprocesses and temporal activity/snapshot-fencing tests. Release `.app` build, resource loading, ad-hoc verification and plist lint passed; earlier disconnected own-view visual confirmation remains recorded separately.

Eleven actual engine checks passed: the read-only management surfaces, explicit hello/activity-snapshot session identity, two bounded public discovery pages with stable/distinct IDs and actual checked-title search. The refined engine identifies the observed AUTH_INVALID category as **credentialStoreUnavailable**, not malformed credentials. The UI shows locally generated permission/availability guidance; no credentials are replaced. No Microsoft login, logout or Keychain approval was attempted.

Native provider-consent/cancellation integration, source-backed discovery/search and explicit installed import are ongoing, not waived. Full owned-PC inventory/audience, legacy package authorization, safe staged installation/hash/expanded-size semantics, signed exact gameplay runtime, save-preserving updates/rollback, full VoiceOver/localization/min-OS and distribution remain open. No install or play action is enabled merely because Xbox Live sign-in succeeds. The user-directed full journey and coordinator-owned adversarial review remain completion prerequisites; this persisted client milestone is not final completion.
