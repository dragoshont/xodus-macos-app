# Public implementation ledger

Baseline: foundation v0.2, 2026-10-03. This ledger records that foundation and the subsequently user-directed native implementation. App and backend remain separate workstreams with reviewable persisted milestones; a client milestone is not a complete consumer release.

**Status vocabulary:** `implemented-fixture` means offline demonstration/checks only; `implemented-client` means native client code exists but provider evidence is tracked separately; `specified` means requirements/design/contract authored; `blocked-live` means an unresolved prerequisite prohibits live release; `planned-live` means work not yet implemented. No row below claims production inventory, game download/install/update or gameplay.

## Active native implementation

The user directed autonomous native development after foundation `44d7338`. This existing app worktree owns the client; the existing public Rust-fork workstream owns management and XAL auth. No duplicate auth provider or private runtime source is imported. [Native integration](NATIVE-INTEGRATION.md) records the exact producer/schema pin and actual evidence.

| Work | Status | Implemented scope | Evidence / remaining gate |
| --- | --- | --- | --- |
| C-TRANSPORT | implemented-client | Codable1.0 models, producer-schema validation, bounded supervised stdin/stdout JSONL, correlated results, deadlines, EOF/nonzero handling and owned-process cleanup | 130 Mac management checks plus ten actual bounded engine checks; no gameplay implication |
| C-ACCOUNT | implemented-client | Native status/sign-in/poll/cancel/logout UI, no tokens/redirects in Swift, commit/cancel-race messaging, explicit user action and capability checks | Published auth/schema pin passes; actual status reports AUTH_INVALID; provider-consent integration remains open |
| C-CATALOG | implemented-client | Real bounded public PC Game Pass discovery, observed-products title search, strict provenance/cursor/locale/failure shapes and edition detail | Actual two-page/title-search probe; full Store search and genuine owned-PC inventory remain active gaps |
| C-ACTIVITY | implemented-client | Real catalog-check enqueue/cancel/retry, fenced snapshot/revision/sequence reconciliation and terminal protection | Actual read-only snapshot verified; game installation/recovery remains separate |
| C-INSTALLED | implemented-client | Typed actual managed-registry snapshot, recorded health, scoped Library and independent detail facet | Actual registry read verified; user-selected inspection/import and current filesystem checks remain ongoing |
| C-BUNDLE | implemented-client | Release `.app`, required resources, original icon generator, local ad-hoc signing/plist verification | Mac bundle/resource/self-check/own-view evidence; no notarization/runtime certification/public distribution |

Current discovery milestone: **14 core + 130 management + 24 presentation = 168 checks**, zero failures, plus ten actual bounded engine checks. Default LaunchServices entry starts the included engine with no mode/backend/env setup; normal own-window UI evidence remains separate. Fixture arrays/jobs remain in explicit `--fixture` mode. Any new provider pin or binary needs its own interoperability evidence before a row becomes `implemented-live`. The user requires the full real journey and coordinator-owned adversarial review/findings closure before final completion.

## Foundation delivered

| ID | Status | Output / evidence | Verification |
| --- | --- | --- | --- |
| F-SPEC | specified | PRODUCT/DESIGN; requirements with measurable acceptance; UX, architecture, evidence and release gates | Documentation links resolve; unknowns explicitly retained |
| F-DOMAIN | implemented-fixture | `Sources/XodusCore`: typed access/installability/compatibility evidence, identity, disk plan and queue policy | `swift run XodusFixtureChecks`: 14 checks |
| F-NATIVE | implemented-fixture | `Sources/XodusPreview`: native SwiftUI/AppKit, actual macOS26+ Glass, original image resources, scoped search and simulated flows | `swift run XodusPreview --self-check`: 15 checks; Mac build + bounded own-view/AX evidence in VERIFICATION |
| F-DESIGN | specified | Nine original editable v0.2 SVG/PNG concepts, source/provenance, compact embedded art; unapproved v0.1 archived | Generator/XML/upload-budget checks; Figma revision status in design/README |
| F-PROTOCOL | specified | `docs/BACKEND-CONTRACT.md`, preserved `docs/contracts/foundation-v1.schema.json` | Original proposed protocol **1.0**; current canonical producer schema/client evidence is recorded separately above |
| F-LICENSE | implemented-fixture | GPL-3.0-only grant + verbatim LICENSE; original assets/source included | Runtime/component redistribution remains separate, blocked before shipping |

## Proposed v1 implementation sequence

| Work ID / requirements | Status | Dependencies | App/backend deliverable and required evidence | Gate / test command |
| --- | --- | --- | --- | --- |
| V1-NEGOTIATE / RELEASE-01 | planned-live | F-PROTOCOL | Rust `manage` entry + Swift process adapter; hello/version/capabilities/per-capability audiences; bounded frames and explicit transport errors | Future adapter tests for incompatible major, missing capability, malformed/EOF/interactive stdout. Foundation `sh tools/check.sh` does not prove this |
| V1-AUTH / AUTH-01,02 | blocked-live | V1-NEGOTIATE, D-04 | Approved consent/audience; reuse existing backend Keychain owner; forbid `key-chain-file`; app cancellation/disconnect/account isolation | Prove nonempty validated credential ownership; cancelled/expired/missing-token tests. No token argv/events/logs |
| V1-CATALOG / FIND-01, ID-01 | blocked-live | V1-NEGOTIATE, D-05 | Authorized full-text catalog search/PC edition-package mapping; existing ID lookup is not full search | Market/language/architecture/edition paging and errors; absent catalog must not imply no ownership |
| V1-INVENTORY / LIB-01,02,03 | blocked-live | V1-AUTH, D-04 | Genuine PC purchase/subscription inventory, all pages; source/time/completeness/cached last complete snapshot | Never-played purchase, expired subscription, console-only, partial/offline/unknown corpus; prove audience/modern PC coverage |
| V1-EVIDENCE / DETAIL-01, COMPAT-01 | planned-live | V1-INVENTORY, V1-CATALOG, D-10 | Four independent live facets; OS/architecture/exact runtime evidence, experimental consent, blocked/unknown reasons | No "Verified" after fingerprint change; installed-with-revoked-access and package-unavailable tests |
| V1-PLAN / PLAN-01 | planned-live | V1-EVIDENCE, D-05, D-11 | Pinned expiring package plan/digest; storage authorization/reservation and validated destination | Exact free-byte threshold; overflow/negative sizes; plan change/expiry; disk lost mid-job |
| V1-QUEUE / QUEUE-01,02 | planned-live | V1-NEGOTIATE, V1-PLAN, D-06 | Durable jobs/idempotency, stdout JSONL events, revision/sequence replay and snapshot reconciliation | Crash/power loss at each phase; duplicates/gaps/retention expiry; cancellation race; no success from exit alone |
| V1-INSTALL / QUEUE-01, REMOVE-01 | planned-live | V1-QUEUE, D-06, D-07 | Integrity, staged extraction, managed-path validation, atomic installed registry; default save preservation | Hash/signature/archive traversal/symlink faults; register only verified content; removal preserves unrelated files/saves |
| V1-RUNTIME / RELEASE-01 | blocked-live | D-03, D-07, D-08 | Signed exact Xbox-capable runtime pair/manifest, redistribution review and failure-safe acquisition | Reject tamper/mismatched pair/capability; stock Heroic Wine/CrossOver not substitutes |
| V1-LAUNCH / PLAY-01, OFFLINE-01 | planned-live | V1-INSTALL, V1-RUNTIME, V1-EVIDENCE, D-09 | Supervised game launch and explicit process outcome; access/runtime/file checks; signed offline policy | Missing files/pair, revoked access/offline denial/child failure. Process spawn is not verified gameplay |
| V1-UPDATE / UPDATE-01, REMOVE-01 | planned-live | V1-INSTALL, V1-RUNTIME, D-11 | Stage/verify/promote new pair; retain previous runnable version and separate saves; rollback/remove manifest safety | Fault injection at journal/fsync/rename; previous version survives; modified saves preserved; save-format warning |
| V1-NATIVE / SETTINGS-01, A11Y-01..03, LAYOUT-01 | planned-live | V1-AUTH..UPDATE live adapters | Replace fixture store with live evidence; full keyboard/VoiceOver/focus-return; modern Glass/older fallback, preferences and resizing | Full journey matrix, 820x600..1600x1000, color schemes/contrast/reduced preferences; current snapshots do not prove compositor fidelity |
| V1-I18N / I18N-01 | planned-live | V1-NATIVE | String Catalogs, locale dates/bytes, pseudolocalization and RTL | 30% text expansion and RTL: no clipped control; no title-key identity |
| V1-DIAGNOSTICS / SETTINGS-01, PRIV-01 | planned-live | V1-NEGOTIATE, V1-NATIVE | Bounded/redacted advanced export with user preview | Zero tokens/signed URLs/account identifiers/raw upstream secrets; public fixture mode stays separate |
| V1-ART / D-12 | blocked-live | V1-CATALOG, rights approval | Properly sourced title-specific covers/immersive images; cache/attribution policy | Original illustrations remain labelled placeholders until rights-cleared catalog art exists |
| V1-DISTRIBUTE / RELEASE-01 | blocked-live | All live rows, D-03..08 closure | Real `.app`, signing/notarization/updater/installer, component license/source notices, release matrix | Fresh-install/tamper/offline/update/rollback; no consumer release while upstream authority/runtime gates remain open |

Dependencies are prerequisites, not a promise of execution order or access. D-IDs refer to [the decision register](RESEARCH.md). Existing private runtime/token prior art is reported evidence, not code imported into this app or a closed app implementation row.

## Commands and evidence policy

**Actual native command:** `sh tools/check.sh` builds and runs core, management and presentation dependency-free checks on the isolated Mac. Foundation ran 29; the current discovery milestone runs 168. `swift test` did not pass because XCTest/Testing are absent in that CLT; no fake test-framework shim is provided. Hosted workflow results must be read separately.

**Actual design commands:** `python3 tools/generate_mockups.py`; `swift tools/render_mockups.swift`; original art reproduction/export commands in design/README. Optional `swift run XodusPreview --export-preview <explicit-directory>` renders only this app's own views and exits; no desktop capture.

Future live rows need their own committed runner commands, fault-injection fixtures and evidence before status changes to `implemented-live`. Never copy fixture check success into a live row. The user pre-approved overnight development after this foundation; the coordinating session owns subsequent work partitioning and the requested final adversarial review with **gpt-6-astra / high**. That review is not performed or claimed on this foundation branch.
