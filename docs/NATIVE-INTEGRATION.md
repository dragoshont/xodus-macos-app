# Native management integration

This is implementation work beyond the immutable foundation at `44d7338`. It is **not a consumer-ready game launcher**.

## Implemented client and native surfaces

`Sources/XodusManagement` implements exact protocol 1.0, request IDs, schema validation against the producer's pinned schema, typed capability objects, bounded UTF-8 JSONL and a supervised native `Process`. It never scrapes interactive output or uses runtime-service IPC as management.

Each request is correlated to its expected command-specific result definition. EOF, malformed/truncated/oversized frames, wrong IDs/shapes, unexpected major/minor, timeout and nonzero exit invalidate the connection; exit zero cannot supply a missing result. Output/event buffers and outstanding requests are bounded. stderr is drained and discarded with a byte limit, not retained as diagnostics. Error messages shown by the app are generated locally from validated error codes, not raw upstream text.

Closing the client first closes stdin for owned-child cleanup, waits for the engine to exit and release its state lock, and applies bounded signal escalation to that exact owned process if needed. Reconnect does not race the old process's lock. The app does not stop another runtime or game.

`LiveSession` and the native views implement a real default development shell: account status, explicit sign-in/cancel/logout actions, scoped partial catalog, edition detail, catalog-check cancellation/retry and authoritative activity snapshots. Native sign-in is backend-owned; the Swift app never receives tokens, redirect fragments or raw provider errors. Optional agreed flow metadata is consumed only through the bundled producer schema and negotiated capabilities. New sign-in is always an explicit user action, never startup or a test action.

Sign-out clears account-bound UI evidence before the operation and is shown as signed out only after the backend confirms removal. Engine/Keychain errors remain errors. A transport failure invalidates credentials/evidence in the UI rather than silently falling back to invented games.

Catalog data is **observedPublicProducts**, with partial coverage, not full Microsoft discovery or an owned library. Request market/language, page cursor and cache revision stay bound together. Duplicate identities and contradictory product/edition scope are rejected. This public catalog cannot promote entitlement from unknown. Catalog checks are not game downloads; the activity UI names their actual operation.

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

The native authentication implementation pin is `dragoshont/xodus-macos`, branch `dragoshont-xodus-launcher-management`, commit `b9cd60bf51cd4cb8e864318cd0c4316453b4b8df`.

Canonical committed schema SHA256:

`b27dab79d05f985eb39ffbd638cab0dbd69e831fd37d29ace414f517229ba7f2`

Committed LF bytes were independently verified after downloading the immutable producer pin. Git blob: `bfb4aa02e2ccb0fa3b1a3b47972b3655ac9861f6`.

`docs/contracts/management-v1.schema.json` is the producer's canonical scoped schema. `tools/sync_contract.py` copies its exact bytes to the Swift resource. `Tests/ManagementChecks/Fixtures` contains its sanitized public positive/negative/evidence fixtures. No private backend source or real account payload was imported. `foundation-v1.schema.json` preserves the original proposal.

The native auth-flow extension and its sanitized corpus are now pinned. The preserved unsigned developer engine input has SHA256 `3fd646ac3eb7bdd2acdbcc3ed3755d2f4e2722ea1a7b4798eae72acb7ac41fd7`. Local ad-hoc signing during embedding changes the executable bytes; the packaged copy has SHA256 `39df33fbac4334df12de39fb2e345a1ac64eb9e4330bb7a1f78de59b6fc26976`. **Provider consent remains separate from read-only/schema/build verification.** No successful account login is claimed merely because the native UI compiles.

## Developer application

On the isolated Mac:

```sh
sh tools/check.sh
sh tools/build_app.sh
open dist/Xodus.app
```

The `.app` includes a release executable, required SwiftPM resources, original native icon and a development bundle identifier. An optional explicit management-engine argument embeds a matching local development build. Its native auth worker re-executes the same binary and returns its session through a backend-private inherited socket; the app receives status only. It is ad-hoc signed and locally verified, **not notarized or released**. No Wine/runtime payload, real library or credential cache is bundled.

Settings provides a native engine picker, account controls, explicit catalog market/language, advanced public-product lookup and a bounded redacted diagnostic preview. Backend discovery in a developer bundle does not establish signed runtime certification.

`--fixture` opens the separate, labelled original design preview. Switching to it disconnects live work first. Fixture data never populates the live app. `--export-live <directory>` deliberately suppresses backend connection and renders only a disconnected shell, so its images cannot expose account/library content.

## Evidence and still-open gates

At this client milestone, `sh tools/check.sh` passed on the Mac: **14 core + 118 management + 24 presentation = 156 checks**, zero failures. The management set includes all 68 positive, ten negative and four evidence-edge producer frames, typed auth/registry results, real mock subprocesses and temporal activity/snapshot-fencing tests. Release `.app` build, resource loading, ad-hoc verification, plist lint and disconnected own-view exports also passed.

Seven actual engine read-only checks also passed against both the preserved input and its locally signed embedded copy: hello, explicit capability gates, invalid saved-credential failure, partial observed catalog, durable activity, management-only registry and redacted diagnostic preview. **Actual `auth.status` returned AUTH_INVALID**, not a valid account; it was reported for backend status/error repair. No Microsoft login, logout or Keychain approval was attempted.

Native provider-consent/cancellation integration, source-backed discovery/search and explicit installed import are ongoing, not waived. Full owned-PC inventory/audience, legacy package authorization, safe staged installation/hash/expanded-size semantics, signed exact gameplay runtime, save-preserving updates/rollback, full VoiceOver/localization/min-OS and distribution remain open. No install or play action is enabled merely because Xbox Live sign-in succeeds. The user-directed full journey and coordinator-owned adversarial review remain completion prerequisites; this persisted client milestone is not final completion.
