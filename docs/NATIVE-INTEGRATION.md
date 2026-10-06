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

The client retains typed `installed.snapshot` wire responses, but the current
producer returns a constant empty vector: no populated durable registry or Mac
scan is implemented. Library explicitly remains unavailable and product detail
keeps This Mac as Not checked. Empty responses are not evidence that no games
are installed; failed refreshes retain only non-current wire snapshots.
Public catalog `notInstalled` metadata is not treated as a whole-Mac installation
scan. User-selected, read-only inspection now uses `installed.inspect` through a native
directory-only picker with alias resolution disabled. The result must echo the
selected path exactly and stays separate from the managed registry. The producer
reads only 196 non-key metadata bytes (156 + 40) from the exact marker; header
GUID/PDUID/contentID are not Store product/edition/package IDs. Missing, aliased or
malformed markers produce explicit errors. No scan, adoption, game-file integrity
claim, entitlement promotion or launch occurs.

## Producer pin

### Separate runtime configuration consumer

Native Settings now share a bounded four-provider section with fixture Settings.
`RuntimeProviderSettings` holds in-memory declarations with initial nil selection;
its action uses `RuntimePlanClient`, not `LiveSession` authentication or C95.
Required nullable fields are explicitly encoded as JSON null. The client uses
the selected trusted executable's sole `runtime-plan` argument, filtered
nonsecret environment, nonblocking pipes, explicit stdin EOF, finite deadline
and exact-owned-process cleanup. It validates strict unique JSON keys, canonical
schema, configuration echo and configuration-hash/generation path correlation.
Nonzero exit discards even valid-looking output. Pending cancellation cannot
publish a late plan. No component path picker/inspection, provider launch,
prefix creation, save reuse, install/play promotion or production-engine trial
is included.

Normal application termination now fences new planning/connect requests and
awaits both management disconnect and runtime-plan cancel/cleanup/reap through
one shared coordinator. A missing management connection never bypasses the
planning shutdown. Failure refuses Quit with explicit state and permits
reconciliation/retry, rather than abandoning an owned process. The normal
coordinator is checked using actual neutral children, without an NSApplication
Quit event, GUI manipulation or production engine.

Source producer is independently frozen
`9ef0f298481fb48840734b538e0f6d22e1c98ff3`; schema LF SHA256
`90c094e4585af059b5ebcfc3201260362e88aa642b50ec0388a03427260d55e9`
and fixture SHA256
`76a0d791c99a6c77e12581a4361dbe6e37a0dbd29f2e556ef292bbbc360bc40c`.
The schema is a separate bundle resource; C95 and the reviewed Swift auth-host
source remain unchanged. This integration is source/headless only, not deployed
or a claim of any installed/runtime/game qualification.

The current schema/fixture pin is public producer commit
`c42e21aee18da893546cca94cbee09820bcbca95` in `dragoshont/xodus-macos`,
branch `dragoshont-xodus-launcher-management`: 88 positive, 47 negative and four
independent evidence-edge frames. This additive contract includes public
`catalog.query`, read-only `installed.inspect` and explicit `auth.verify`; capabilities are negotiated from the running producer, not
copied from a fixture.

Canonical committed schema SHA256:

`5b588ae7339a11850339e4979ebd14a577f37e2c8d94e02dab85969d3400c544`

`auth.verify` accepts only a canonical content UUID, returns exactly
`{"verified":true}`, or one of seven strictly matched safe failure stages. It
performs no automatic retry, sign-in, account refresh or credential write.
Success proves only an authenticated package read, not ownership, installation
or a license. No authenticated live outcome is claimed until the matching pair
is independently admitted and its single explicit probe completes.

Committed LF bytes and all four sanitized fixture hashes were independently verified from immutable public Git objects. A transient GitHub network outage was handled with that exact public-only fallback, not mutable backend source or private data.

`docs/contracts/management-v1.schema.json` is the producer's canonical scoped schema. `tools/sync_contract.py` copies its exact bytes to the Swift resource. `Tests/ManagementChecks/Fixtures` contains its sanitized public positive/negative/evidence fixtures. No private backend source or real account payload was imported. `foundation-v1.schema.json` preserves the original proposal.

The current deployed development engine source is reviewed public
`e7e61fa820b771099fd90516ccaca056f265966d`, paired with app
`e5a573aaca94f4cee46f591f9f927fcd0df0f782`. Its immutable unsigned input
SHA256 is `304c249ae24fc187533865ebb3d61cd40cec812629c537692e009f54bec22349`;
the separate signed copy is
`4d04fd6c98478574f8b0413de3a2422cebf66dce9c72357629c38cf02e2dbf32`.
The app executable is
`97e423985d1e5193db2cd80b6f2aa9ce546cc167d91ec2337a4653f3dc0bfabe`.
The Swift executable came from a verified native **release** stage; the Rust
engine is an offline/locked **default-dev** build, not a Rust release.

This producer corrects an unsupported local decoding predicate: original
Passport request builders forward the issuer's opaque ticket representation,
while the distinct proof key and SOAP cryptography still require strict
validation. Bounded/reparsed/nonblank ticket, kind/context/expiry, isolation,
cancellation and atomic-commit checks remain. Two native regressions failed
before the correction and passed afterward; 59 selected native checks passed
in one bounded run. These are not captured provider-format or authentication
success evidence. Same continuity review closed the exact combined source.

One owned native authentication window was subsequently observed. The flow
was already active before an agent Sign in guard, which refused before AXPress;
activation source is unknown and no duplicate entry was sent. Human completion
and credential commit are **not verified**. Sign-in and deployment are now user-paused; current window/worker presence is
not re-inspected or inferred. No agent navigation, approval, credential entry,
polling or restart is authorized.
The subsequent bounded native UI source correction is separately staged only;
it does not mutate that deployed app, engine or authentication flow.

The preceding reviewed eighteen-pair diagnostic engine source was
`2acb452a7ee66b2c9d3ad75ecf85e2be2f94fbc3`, paired with app
`5ae30fd4bd4e17cb235857e5c41fba1627c317f7`.
Preserved immutable input is `xodus-cli-xml-proof-v1-8a4b8d56aad18841`,
SHA256 `8a4b8d56aad18841326834e5ad57860072560f4739963323875ffa52d41a545b`;
the separate signed embedded copy is
`125a05dd0a2a577cc8fc71e4d3eaf324b9c70b3d409a54fd5b0eeef17ad45cf4`.
Deep signature, exact C95 resource/provenance, fresh parent/child ownership and
nine actual read-only checks passed. This is a local development pairing, not a
certified runtime or successful sign-in. The previous bace/da0 342/5d and
e604/360e8bf 47f/c50a pairings and all older immutable inputs remain preserved.

The historical first human-entry engine source was
`2a47eafc930603773583ce4c1d6be89a2f0ccd60`. Its preserved unsigned input is
`xodus-cli-soap-nonces-v1-57d4500d6de922d6`, SHA256
`57d4500d6de922d644071ff6749b662c56d75f5f4646da2a884a363169373c0b`;
the separate ad-hoc-signed embedded copy has SHA256
`7a6edd58efa81f567ebf7ecc8c7cf089fb7fc155533e2db28ab797111ec2230d`.
C95 schema/operations are unchanged. This is a necessary correction on the real
Store authentication decoder path: duplicate or empty derived-key nonce IDs
are rejected rather than silently overwritten/accepted. The producer pin was
confirmed by the backend before the user-directed retry; no unsigned sealed
artifact was changed. Historical e3129/da548, signed2180 and 57d/signed7a6e pairings are preserved,
not reused as the current diagnostic build.

It retains the reviewed public search/inspection behavior. The source-only app
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
The user-directed retry activated the exact enabled native Account sign-in
button once through AXPress, using `auth.begin`. The app subsequently displayed
its fixed failed-flow message, not saved credentials or successful sign-in.
No Microsoft credentials, code, consent or Keychain decision was automated or
read; there was no automatic retry. The flow's failure needs further diagnosis.
The retry build's generic label does not expose its in-memory optional error,
so no exact failure code/stage was recovered. A subsequent source-only native
correction shows validated flow failure codes with local wording, never raw
messages, and explicitly preserves unknown stage when evidence is absent.
No debugger/status call/retry was used to recover that old tuple; its cause
remains unknown. The later reviewed diagnostic source was separately deployed,
not injected into the original failure.
The subsequent diagnostic-only source agreement closes the optional details to
ten exact AUTH_INVALID stage/reason pairs, mapped to local guidance; unknown,
extra or incompatible values remain unavailable stage and are not retained or
rendered as diagnostics. See [the exact object](BACKEND-CONTRACT.md).
Final original diagnostic source `360e8bf` passed 333 full checks and hosted CI.
The successor continuity reviewer closed that app/producer delta with no
significant issues; the cancelled original reviewer supplied no report 40/41
approval. The user-directed close/relaunch used only the verified idle owned app.
At verification the new pair was app 92655 / child 92660. One new agent-mediated
native entry returned `AUTH_INVALID/devicePreparation/providerProofInvalid`.
That legacy classification does **not** establish a cryptographic failure:
it covers an unsupported device response or absent/invalid proof. No successful
credential commit, Microsoft UI observation or owned-library proof was inferred.

The subsequent source batch replaces bespoke navigation with a system toolbar,
corrects that local proof wording and adds four agreed static device reasons
(fourteen closed pairs total). The coordinator's same continuity review closed
that app delta and the backend response-wrapper refinement with no significant
issues. Exact app source passed 353 hosted checks; the producer passed its 45
native checks and qualified gates before sealing. The reviewed pair was then
deployed after fresh idle-flow guards and graceful exact-owned quit.

One user-authorized native entry on the new pair returned
`AUTH_INVALID/devicePreparation/tokenStructureInvalid`, with the visible
"Microsoft sign-in could not start." explanation. No pending Cancel control
or auth child remained at observation; an owned native authentication window
was not observed. The particular structure guard is still unknown. No raw
provider data, credentials or OS decisions were inspected or automated.
The next concrete backend fix remains separate from source-review closure;
the unchanged failing engine is not repeatedly retried. Exact hashes,
historical local failures and independently passing evidence are recorded in
[verification](VERIFICATION.md).

### Reviewed static token subsites and observed cipher failure

The coordinator and sole consumer explicitly agreed four additive
`devicePreparation` reasons with the producer before implementation:
`tokenKindInvalid`, `tokenAudienceInvalid`, `tokenCipherInvalid` and
`tokenSecretInvalid`. The consumer retains all fourteen older pairs, including
coarse `tokenStructureInvalid`, and accepts only the exact three string keys
for `AUTH_INVALID` / `nativeConsentFailure`. Static local copy explains only
unsupported format, unmatched context, unprocessable payload or missing/invalid
proof; no values or assumed provider/cryptographic cause are shown.
The complete 398-check app suite passed locally and in hosted CI. The same
continuity review closed both source deltas, and the producer passed 54 native
checks before sealing. Deployment preserved originals and separately signed the
copied engine after fresh idle-flow guards and graceful exact-owned retirement.
One authorized native entry on app 41090 / engine 41093 returned
`AUTH_INVALID/devicePreparation/tokenCipherInvalid`, with zero pending Cancel
controls, progress indicators, owned auth children or observed auth windows.
The particular bound/parse/encoding guard is still unknown; a parser regression
does not prove the live proof contained whitespace.

### Agreed minimal cipher subsites (source only)

The coordinator and sole app explicitly agreed only `tokenXmlBoundInvalid`,
`tokenXmlParseInvalid` and `tokenCipherEncodingInvalid` before implementation.
All eighteen older reasons remain accepted, including coarse `tokenCipherInvalid`.
Exact keys, AUTH_INVALID-only gating, C95 and lifecycle behavior remain unchanged.
Local copy reports only a supported processing limit, unreadable required format
or unprocessable encoding; no numeric limit, data or assumed crypto/provider
cause is shown. This twenty-one-pair source batch does not relax token acceptance.
The historical source-only phase left 8a4b/125a untouched. Later same-reviewer
closure and native gates authorized the baf/e5 diagnostic pairing, followed by
the e7/e5 admission correction recorded above. The twenty-one diagnostic mappings
and all authentication lifecycle behavior remain unchanged in the current UI
source correction. Live visual verification and authentication/deployment are
paused. Source work does not imply approval to act on an existing window.

## Bounded native UI source correction

Live and fixture views share the existing native search editor/bindings with
standard `NSSearchField` appearance and clear control, without a custom capsule
or forced dark/white search styling. Following the latest user-directed header
revision, compact search now shares the principal toolbar group with navigation
instead of appearing inside the hero. Command-F continues to request its editor.
Real macOS 27 `.tabs` uses a segmented 14-26 fallback; source requires SDK 27+.
Original artwork extends behind system chrome, notices move into content, and
the visible title is hidden without discarding window/menu/Dock identity.
Account separates scrolling status/explanation content from one adaptive action
footer; a bounded sheet shrinks decoration before controls. Existing auth
predicates, identifiers, cancel/dismiss safeguards and Account refresh remain.
The Scene owns the hidden-title-bar/unified toolbar; redundant post-creation window
overrides and unconditional legacy activation have been removed.

Headless presentation checks allocate only detached native controls and
synthetic layout views. They do not instantiate the Account flow's refresh task,
show a window or contact an engine/Keychain/provider. An additive isolated
native release stage is not a signed/packaged/deployed app. Both-appearance,
compositor, preference, resize and assistive-technology confirmation remain
pending; source/framework/AX-role evidence is not visual conformance.

## Dedicated Swift native authentication host: source only

`XodusAuthHost` is a dependency-free AppKit/WebKit/Foundation SwiftPM executable,
not a second management transport. The private contract and neutral corpus are
pinned to public producer `bb6397033fc38497a73684a9ecdb2929caba1f63`;
schema SHA256 is
`c7ca7de8ee8a610b71e9e458f13469554467dd2632f88d35317a1ce2646af430`,
fixture SHA256
`d864e96079dc5292f6c078fb2be37c870f1cf4be114edc6e68e0984a555d0d24`.
It uses an anonymous inherited socket, strict bounded correlated frames,
the original remaining monotonic budget, a fresh nonpersistent WebKit store,
trusted main-frame/origin/document-generation checks and one-shot exact
seven-string legacy handoff. Native callback, genuine navigation, renderer,
checked-JS, close, EOF and deadline failures are explicit static outcomes.
Closing the owned native window, including `NSWindow.close()` paths that bypass
`windowShouldClose`, sends one terminal cancellation and exits the helper.
Unrelated windows do not cancel the attempt. The app reconciles the terminal
flow through `auth.status` and enables an explicit new sign-in; it never retries
automatically or treats closing a window as saved credentials. Neutral checks
exercise hidden AppKit window closure, private-channel EOF, helper exit and the
following user retry without contacting Microsoft.
The additive navigation correction permits all subframe loads, scoped HTTPS
Microsoft top-level redirects and same-view popups without treating ordinary
cancellation/policy interruptions as whole-flow failures. Blank popup initialization
does not replace the current document. This fixes identified brittle handling,
not a diagnosis of the previous brief-window failure.
Rust retains SOAP/proof processing, helper reaping and atomic credential commit.

The source-verified notification compatibility correction mirrors the original
handler's tolerance. Known `getContext` invokes may include unused `args` or other
keys; unrelated notifications and non-JSON strings are ignored. Flat or wrapped
provider DA objects may contain extra keys, but only the seven required strings
enter the unchanged strict `LegacyDA` and private result. A claimed malformed DA
still fails. Untrusted frames/origins receive no callback or DA delivery and do
not terminate the flow. Private wrapper shape, control generation, document nonce,
one-shot delivery, frame limits and writer/commit gates remain unchanged.

The finish-script compatibility correction also handles the original handler's
flat `ServerData`, not only `ServerData.DAProperty`, while forwarding only the
same seven string fields. Known context dispatch preserves the original window
receiver and serialized string argument. These are script-shape and call-semantics
corrections, not broader origin trust or a successful authentication claim.

The compatible producer observation uses the existing failure message only:
`Native sign-in failed: helper.REASON.` with the closed reasons `invalidFrame`,
`invalidNavigation`, `navigationFailed`, `popupUnsupported`, `contentTerminated`,
`javaScriptFailed`, `bridgeInvalid`, `deadlineExpired`, `parentUnavailable`, or
the exact `Native sign-in failed: channelEOF.` / `Native sign-in failed: unclassified.`,
or the fixed boundary messages `Native sign-in failed: tokenExchangeFailed.` /
`Native sign-in failed: helperCompletionFailed.`. These identify failed operations,
not provider error text, and never establish credential commit.
The additional `tokenExchange.STAGE` literals are limited to `requestBuild`,
`requestSerialization`, `requestTransport`, `requestTimeout`, `httpClientError`,
`httpServerError`, `httpStatusRejected`, `responseParsing`, `responseSignature`,
`responseCryptography`, `responseEncoding`, `continuationRequired`,
`faultWithoutContinuation` and `continuationRejected`. The exact
`Native sign-in failed: exchangeRetentionFailed.` is also accepted. No unknown
stage, prefix match, extended message or provider exception is displayed.
Account Details accepts these exact strings only with the existing
`AUTH_INVALID / nativeSignIn / pipelineFailed` tuple; all other message text remains
undisplayed. No new wire fields, logs, provider content or secret-bearing diagnostics
are introduced. Qualification and a fresh signed producer/consumer pair precede any
new live sign-in attempt.

Configuration binds a fixed owned bundle executable, protocol version and
SHA256 through nonsecret flags. A packaged `.app` missing both helper and receipt,
an incomplete receipt pair or an invalid helper fails before engine launch,
with a static helper-specific recovery message and without PATH selection.
Unpackaged anonymous/developer checks may still omit the binding. This local
helper check does not qualify the selected engine or attest its source.
The packaging script includes the shipping helper and post-sign metadata from
clean source, but this new revision has not been executed. Private synthetic
host-check resources are excluded from the shipping source/resource set.
The deployed e7 producer lacks the new concurrent engine-EOF guardian; the
paired producer must implement it through issuance, cleanup and publication,
then pass the agreed engine-only death/write-half/race tests and combined review.
Matching C95 alone is not this pairing gate.

The reviewed producer is `9ef0f298481fb48840734b538e0f6d22e1c98ff3`,
including auth producer `94353b5cc3196a2b73b89655855ec50c31d35b81`.
The old e7/304 engine does not support the three native-host flags; omitting them
selects its old legacy path, not the new Swift host. HELLO's supported auth
capabilities, version and C95 hash do not establish this producer pairing.
`XODUS_BACKEND_PATH` and the explicit developer engine picker are nonshipping
only. Shipping has neither override and cannot borrow bundled helper evidence.

The new [controlled local admission](SHIPPING-ADMISSION.md) tooling verifies
externally pinned unsigned CLI/provenance and exact source/tree/profile/features,
then separately signs and generates compiler-bound signed engine/helper pins.
The runtime rejects missing/mismatched pins, helper receipt source/version/hash
and nonfixed paths before execution; pure planning shares this boundary.
The committed pin template is nil, not an arbitrary-engine grant. This is the
approved external operator gate made enforceable for one local pair, **not**
generic distribution attestation. The older owner's sealed e7 provenance is
not evidence for943/9ef. Do not reuse304/4d04,
infer source from HELLO or a binary hash, or fabricate a seal. Build only in a
new isolated canonical-Git stage, verify the final helper receipt/hash/version,
resources and complete bundle, and preserve the prior app as rollback. A verified
pair is launch readiness, not successful authentication.

Detached synthetic WebKit/channel checks are not a provider trial, OS passkey
association, biometric-prompt diagnosis or authenticated/committed account.
Apple's [Supporting passkeys](https://developer.apple.com/documentation/authenticationservices/supporting-passkeys)
requires an associated domain for WKWebView passkeys; migrating this legacy
flow to Swift does not establish Microsoft association. Apple's
[public-key-credential browser entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.web-browser.public-key-credential)
is an approved browser capability, not an ad-hoc launcher fix. Unknown passkey
eligibility is not a reason to block a possible password/code flow, change client
IDs or disable MFA. The reported prompt's cause remains unknown.
Production stdio is discarded and core dumps are disabled where possible;
OS crash-report suppression is not promised. GUI focus/input/capture/inspection
and deployment remain paused while the user's game work owns the desktop.

## Developer application

Only after explicit desktop/CPU release, source/paired-artifact approval and
fresh owned-process checks, in a new isolated canonical-source stage:

```sh
sh tools/check.sh
sh tools/build_app.sh /absolute/reviewed/engine UNSIGNED_SHA BYTES PROVENANCE_SHA PROVENANCE_BYTES APPROVED_APP_COMMIT APPROVED_APP_TREE /absolute/owned/output --signing-identity CERT_SHA1
```

The script reports a new distinct bundle and external package receipt; it never
opens a window or replaces `dist/Xodus.app`. Launch requires separate approval.
The supplied identity must already exist in the OS Keychain; provisioning and
private-key prompts require separate human approval. Fixed signing identifiers,
artifact-level designated-requirement comparison, the separate requirement for
independent approved build evidence, and prior-package-receipt-bound UI-only CLI
preservation are described in [shipping admission](SHIPPING-ADMISSION.md).

The existing deployed `.app` includes a release executable, SwiftPM resources,
original native icon and development bundle identifier. Its Rust native worker
re-executes the same engine and returns a session through a backend-private
socket; the main app receives status only. It is ad-hoc signed and locally
verified, **not notarized or released**. The unexecuted packaging revision adds
the Swift host and requires a matching new producer; it does not replace this
preserved pairing. No Wine/runtime payload, real library or credential cache is
bundled.

Settings provides account controls, explicit catalog market/language, advanced public-product lookup and a bounded redacted diagnostic preview; the native engine picker exists only in nonshipping development. After preview, a native save panel can save exactly the displayed counts-only summary atomically off the main actor. Unreviewed/stale preview and nonlocal destinations are rejected; filesystem errors are visible, not success. No account data, raw logs, URLs or personal paths enter this summary. Backend discovery in a developer bundle does not establish signed runtime certification.

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

The historical app retirement/export review-fix milestone passed one full `sh tools/check.sh` invocation
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
