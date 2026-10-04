# Native management integration

This is implementation work beyond the immutable foundation at `44d7338`. It is **not a consumer-ready game launcher**.

## Implemented client and native surfaces

`Sources/XodusManagement` implements exact protocol 1.0, request IDs, schema validation against the producer's pinned schema, typed capability objects, bounded UTF-8 JSONL and a supervised native `Process`. It never scrapes interactive output or uses runtime-service IPC as management.

Each request is correlated to its expected command-specific result definition. EOF, malformed/truncated/oversized frames, wrong IDs/shapes, unexpected major/minor, timeout and nonzero exit invalidate the connection; exit zero cannot supply a missing result. Output/event buffers and outstanding requests are bounded. stderr is drained and discarded with a byte limit, not retained as diagnostics. Error messages shown by the app are generated locally from validated error codes, not raw upstream text.

Closing the client first closes stdin for owned-child cleanup, waits for the engine to exit and release its state lock, and applies bounded signal escalation to that exact owned process if needed. Reconnect does not race the old process's lock. The app does not stop another runtime or game.

`LiveSession` and the native views implement a real default development shell: account status, explicit sign-in/cancel/logout actions, scoped partial catalog, edition detail, catalog-check cancellation/retry and authoritative activity snapshots. Native sign-in is backend-owned; the Swift app never receives tokens, redirect fragments or raw provider errors. Optional agreed flow metadata is consumed only through the bundled producer schema and negotiated capabilities. New sign-in is always an explicit user action, never startup or a test action.

Anonymous startup does not read the Keychain. Account initially remains unchecked;
explicitly opening Account requests a noninteractive saved-profile check.
**Check status** remains available during pending sign-in. A new sign-in requires
fresh, confirmed signed-out status; expired/invalid profiles instead expose a
confirmed launcher-only disconnect. An unavailable store never causes deletion.
The original GUI startup
was observed to time out specifically in `auth.status`, despite the equivalent
SSH read failing promptly with `credentialStoreUnavailable`. Removing that
automatic read preserves anonymous browsing without approving any native consent.
The coordinated producer fix makes management-profile status reads noninteractive
and bounds them to two seconds without blocking public dispatch. OSLog records process start, negotiation and the canonical command
name on timeout only; no paths, arguments, IDs, credentials or upstream messages
are logged.

Sign-out clears account-bound UI evidence before the operation and is shown as signed out only after the backend confirms removal. Engine/Keychain errors remain errors. A transport failure invalidates credentials/evidence in the UI rather than silently falling back to invented games.

Human-interactive `auth.begin` preparation and `auth.logout` have separate finite
600-second transport budgets; ordinary reads retain 30-second defaults. A
mutation failure invalidates the pre-mutation account freshness and never causes
a blind retry. Pending flow reconciliation survives transient unavailable-store
or retryable responses. A rejected cancellation during credential commit resumes
polling with the original monotonic deadline instead of claiming cancellation.
Terminal flows cannot regress to a late pending snapshot. At deadline, the app
asks for current status rather than manufacturing a terminal outcome.

Discover now requests one bounded public **pcGamePassDiscovery** page at a time from the official Microsoft PC Game Pass feed. Request market/language, cursor and corpus revision remain bound together. Successful public products also seed **observedPublicProducts** checked-catalog
title search, which remains distinct from real **catalog.query** network search.
The latter uses Microsoft's public Store Edge search with source-backed PC product
checks, exact query echo, scope-bound opaque cursors and visible per-item failures.
Native input is explicitly trimmed before sending; duplicate identities and
contradictory product/edition scope are rejected without merging same-title IDs.
This public catalog cannot promote entitlement from unknown. Catalog checks are
not game downloads; the activity UI names their actual operation.

Each attempted page item is either a product or a visible lookup failure. An
all-failure response remains an error: only command-correlated
`failedDiscoveryData` / `failedQueryData` is retained, validated separately from successful discovery
whose products cannot be empty. No arbitrary error payload or raw upstream message
is displayed. Continuation remains visible even if every item on the first page
failed. A genuine zero-source query is distinct from failed metadata checks.
Stopping search fences late results but does not claim to abort HTTP.
Catalog requests are coalesced into one active request and one latest queued
query/market/language scope. Cancelling a view task does not free a producer
operation; newer input replaces the queued scope, and stop drops it. Pagination
retains its cursor/failure semantics. Source-level `PACKAGE_UNAVAILABLE` without
batch details stays a recoverable typed error; present malformed/null details
remain protocol failures rather than being silently discarded.
The native request allows 45 seconds around the producer's
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
scan. User-selected, read-only inspection now uses `installed.inspect` through a native
directory-only picker with alias resolution disabled. The result must echo the
selected path exactly and stays separate from the managed registry. The producer
reads only 196 non-key metadata bytes (156 + 40) from the exact marker; header
GUID/PDUID/contentID are not Store product/edition/package IDs. Missing, aliased or
malformed markers produce explicit errors. No scan, adoption, game-file integrity
claim, entitlement promotion or launch occurs.

## Producer pin

The current schema/fixture pin is public producer commit
`e3129cee422305657b945d35daf2f780ffe98e2b` in `dragoshont/xodus-macos`,
branch `dragoshont-xodus-launcher-management`: 79 positive, 20 negative and four
independent evidence-edge frames. This additive contract includes public
`catalog.query` and read-only `installed.inspect`; capabilities are negotiated from the running producer, not
copied from a fixture.

Canonical committed schema SHA256:

`c95c3fabdf114f89329d2361e76421e7b47be4c113f56c2381e64d437e44f749`

Committed LF bytes and all four sanitized fixture hashes were independently verified from immutable public Git objects. A transient GitHub network outage was handled with that exact public-only fallback, not mutable backend source or private data.

`docs/contracts/management-v1.schema.json` is the producer's canonical scoped schema. `tools/sync_contract.py` copies its exact bytes to the Swift resource. `Tests/ManagementChecks/Fixtures` contains its sanitized public positive/negative/evidence fixtures. No private backend source or real account payload was imported. `foundation-v1.schema.json` preserves the original proposal.

Current enabled-inspection engine input SHA256:
`da548dd5abe4c32dc17035817d1a809a31c8eb19e615f26dad079a245cf72178`.
Its ad-hoc-signed embedded copy has SHA256
`2180d02dca9300d08c91384207fed6acebdeaaa9d0c309bc0fd28a7fcf7b2296`.
It includes the retained-review-closed R05/R06/R07 producer fixes; its inspection
adapter/primitives were approved by that same review. The source-only app
R01-R04 fixes closed at `fb66a2d`, R08/R09 at `6750219`; the `db0bf21`
picker/consumer delta had no significant issues. Subsequently confirmed R10
shared-retirement fixes closed at `f967f5c` in retained report 13, with no
significant diagnostics issue. Separate backend R11 source closure followed in
report 14. The source/UI hold is cleared; human provider consent and the full
game journey are not completed or inferred. Historical producer
hashes, including superseded `58f5` and `35f0`, remain in
[verification](VERIFICATION.md); they are not current readiness builds.
**Provider consent remains separate from read-only/schema/build verification.**
No successful account login is claimed merely because the native UI compiles.

## Developer application

On the isolated Mac:

```sh
sh tools/check.sh
sh tools/build_app.sh
open dist/Xodus.app
```

The `.app` includes a release executable, required SwiftPM resources, original native icon and a development bundle identifier. An optional explicit management-engine argument embeds a matching local development build. Its native auth worker re-executes the same binary and returns its session through a backend-private inherited socket; the app receives status only. It is ad-hoc signed and locally verified, **not notarized or released**. No Wine/runtime payload, real library or credential cache is bundled.

Settings provides a native engine picker, account controls, explicit catalog market/language, advanced public-product lookup and a bounded redacted diagnostic preview. After preview, a native save panel can save exactly the displayed counts-only summary atomically off the main actor. Unreviewed/stale preview and nonlocal destinations are rejected; filesystem errors are visible, not success. No account data, raw logs, URLs or personal paths enter this summary. Backend discovery in a developer bundle does not establish signed runtime certification.

Default LaunchServices startup was exercised with `open Xodus.app`, no mode,
backend flag or environment override. After fixing the automatic account read,
the included-engine child survived beyond the original timeout and the normal
Library/Discover/Downloads/Account controls passed bounded Accessibility
interaction. The committed `tools/check_live_ui.applescript` requires the exact
owned PID, bundle identity, non-fixture window and stable native control identifier;
it refuses blind interaction and logs only allowlisted, locally authored labels.
Its `InspectCancel` action was exercised against the normal native app: it opens
only the explicitly labelled game-folder picker, cancels without selecting a
directory and confirms the picker closed. The inspection button has explicit
AX label/identifier/button/press semantics. Picker contents and directory names
are not logged. Cancellation does not call `installed.inspect`.
This is not a full VoiceOver or provider-consent test. Missing included engines do not silently select a remembered
developer binary. User-mediated store authentication will use a backend-isolated
launcher Keychain profile, not implicit CLI/private-worker credential import.

`--fixture` opens the separate, labelled original design preview. Switching to it disconnects live work first. Fixture data never populates the live app. `--export-live <directory>` deliberately suppresses backend connection and renders only a disconnected shell, so its images cannot expose account/library content.

## Evidence and still-open gates

The current app review-fix milestone passed one full `sh tools/check.sh` invocation
on the Mac: **14 core + 189 management + 24 presentation + 51 native session =
278 checks**, zero failures. The native session set uses mock child processes and
the actual `LiveSession` coordinator, not real Keychain/provider operations.
It covers R01-R04 recovery, permission-preserving disconnect gating,
failed-mutation freshness, genuine empty query, stop-search fencing, selected
inspection scope, R08/R09, fourteen R10 overlapping-retirement/startup checks and
five reviewed-summary file/error/privacy checks. Five delayed edits with old view tasks cancelled
produce only two requests with maximum concurrency one; the newest captured
query/locale completes without a manual refresh or producer capacity error.
Management
tests include 31-second synthetic preparation/logout with concurrent public reads.
The release bundle passed resource, plist and ad-hoc-signature checks; earlier
disconnected own-view visual confirmation remains separate.

Twenty-two actual management checks passed against the signed enabled-inspection
copy: bounded Store/discovery pages, exact session identity, registry/diagnostics,
checked-title search, owned-process exit and read-only synthetic marker
inspection. The original 4096-byte fixture is authored in the committed runner,
not a real game. Exactly 196 metadata bytes/digest/version and unchanged marker/
registry bytes were verified; missing, aliased and malformed fixtures returned
typed errors and the same connection remained usable. Normal native Account
status, public Halo search and continuation passed bounded own-window checks.
No Microsoft login, logout or Keychain approval was attempted. **A live upstream
zero-source query has not been observed**: arbitrary nonsense can return
suggestions. Deterministic producer/native regressions cover empty-source
behavior separately, not as live empty-search proof.

Expanded reconnect checks exposed a Foundation `waitUntilExit` stall after the
owned child had exited; the exact mock-only stack was sampled. Close now observes
exit with a six-second bound around existing exact-PID escalation. Failed shutdown
is explicit, retains the retiring client and blocks reconnect, fixture switching
and application termination until reconciled. Repeated worker reconnect checks
pass; there is no unbounded private run-loop wait.

R10 additionally keeps retiring ownership in a shared operation before the first
suspension. Concurrent disconnect/fixture/quit callers await the same outcome;
failure never clears or replaces the retiring client. Connection reservation,
lifecycle revision and waiter gating fence the entire reconnect, including
post-negotiation/snapshot continuations. Engine selection and reconnect are
disabled during the transition. Actual held-EOF children exercise overlap and
a test-only short negative observation; production still uses six seconds.
The real application subsequently quit/relaunched with both owned processes
observed gone before another instance opened.

`tools/check_diagnostics_ui.applescript` passed actual native Settings,
counts-only preview and save-panel cancellation. It does not log picker contents,
choose a destination or write a file. Programmatic file regressions use only
owned original synthetic roots and clean them up. The same retained review closed
R10 at `f967f5c` and found no significant diagnostic-summary issue. The unchanged
native Account entry has been prepared for human handoff; no sign-in or approval
has been automated.

Native provider-consent/cancellation integration, source-backed discovery/search and explicit installed import are ongoing, not waived. Full owned-PC inventory/audience, legacy package authorization, safe staged installation/hash/expanded-size semantics, signed exact gameplay runtime, save-preserving updates/rollback, full VoiceOver/localization/min-OS and distribution remain open. No install or play action is enabled merely because Xbox Live sign-in succeeds. The user-directed full journey and coordinator-owned adversarial review remain completion prerequisites; this persisted client milestone is not final completion.
