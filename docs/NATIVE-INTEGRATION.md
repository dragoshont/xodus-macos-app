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
scan. User-selected, read-only existing-install inspection is the next coordinated
backend contract, not permission for a blanket private-folder scan.

## Producer pin

The current schema/fixture pin is public producer commit
`9d024ae079daccafb3437e4b0c67aef735d657bb` in `dragoshont/xodus-macos`,
branch `dragoshont-xodus-launcher-management`: 77 positive, 15 negative and four
independent evidence-edge frames. This additive contract includes public
`catalog.query`; capabilities are negotiated from the running producer, not
copied from a fixture.

Canonical committed schema SHA256:

`655e1ed31772b35a8526ef5a0986557e7f6de689d5c4925ccde7041bc33b5f29`

Committed LF bytes and all four sanitized fixture hashes were independently verified from immutable public Git objects. A transient GitHub network outage was handled with that exact public-only fallback, not mutable backend source or private data.

`docs/contracts/management-v1.schema.json` is the producer's canonical scoped schema. `tools/sync_contract.py` copies its exact bytes to the Swift resource. `Tests/ManagementChecks/Fixtures` contains its sanitized public positive/negative/evidence fixtures. No private backend source or real account payload was imported. `foundation-v1.schema.json` preserves the original proposal.

The bounded Store/discovery probe used implementation
`4de9c2b2e7c114854699e3708d41c12fa73e188d`, unsigned input SHA256
`58f5b80f253d8ee199dc193d3a31cbd1571b641ce309f81bf0430910a6982e83`.
Its ad-hoc-signed embedded copy has SHA256
`5ea5b49610fc9887345234e0d66bc9954f3bf1e78716ab25866802c4f48f324b`.
**That producer is provisional, not review-closed:** the retained reviewer found
an empty-query cache failure and insufficient repeated-source-cursor normalization
(R06/R07). Its positive two-page probe does not validate those edge cases.
A new immutable producer and fresh interoperability evidence are required before
claiming their closure or human sign-in readiness. Earlier discovery pins and
hashes remain historical evidence in [verification](VERIFICATION.md).
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

The current app review-fix milestone passed one full `sh tools/check.sh` invocation
on the Mac: **14 core + 156 management + 24 presentation + 18 native session =
212 checks**, zero failures. The native session set uses mock child processes and
the actual `LiveSession` coordinator, not real Keychain/provider operations.
It covers R01-R04 recovery, permission-preserving disconnect gating,
failed-mutation freshness, genuine empty query and stop-search fencing. Management
tests include 31-second synthetic preparation/logout with concurrent public reads.
The release bundle passed resource, plist and ad-hoc-signature checks; earlier
disconnected own-view visual confirmation remains separate.

Thirteen actual read-only engine checks passed against the preserved input and
signed embedded copy: bounded Store/discovery pages, exact session identity,
registry/diagnostics and checked-title search. Normal native Account status
resolved noninteractively while anonymous discovery stayed connected beyond
35 seconds. These results predate R06/R07 closure and do not prove genuine
empty-source or complete paging behavior. No Microsoft login, logout or Keychain
approval was attempted. The retained coordinator-owned review must separately
close the persisted app fixes and all confirmed backend findings.

Native provider-consent/cancellation integration, source-backed discovery/search and explicit installed import are ongoing, not waived. Full owned-PC inventory/audience, legacy package authorization, safe staged installation/hash/expanded-size semantics, signed exact gameplay runtime, save-preserving updates/rollback, full VoiceOver/localization/min-OS and distribution remain open. No install or play action is enabled merely because Xbox Live sign-in succeeds. The user-directed full journey and coordinator-owned adversarial review remain completion prerequisites; this persisted client milestone is not final completion.
