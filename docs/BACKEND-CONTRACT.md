# Proposed management contract v1

**Design proposal only. Not an endpoint implemented by Xodus today.** The names below are normative for a future adapter review, not evidence that commands exist. Runtime `xodus-service` IPC is separate.

Stable handoff: **protocol 1.0**, [envelope/evidence JSON Schema](contracts/management-v1.schema.json), [implementation ledger](IMPLEMENTATION-LEDGER.md). The schema fixes 1.0 frame structure and exposes reusable `$defs/productEvidence`; operation-specific plan/job/registry request/result schemas, temporal replay validation and a live validator are future adapter work. A negotiated future compatible minor needs its own updated schema; do not use this strict 1.0 schema to guess forward compatibility.

## Transport and negotiation

Proposed entry: `xodus manage --protocol 1`, one JSON request per stdin line, one JSON response/event per stdout line (UTF-8, LF). stderr is redacted human diagnostics, never machine results. No interactive prompts. Max line size 1 MiB; unknown fields ignored only within a negotiated compatible minor; unknown required capabilities fail closed. Never place credentials in argv/stdout/stderr. A private local broker or inherited credential pipe carries secrets separately.

Authentication reuses the backend's existing macOS Keychain token abstraction as a single credential owner. Shipping manifests must disable `key-chain-file`/`.xodus-keyring.ron`. Hello must also expose non-secret **per-capability audience requirements**; the broker obtains scoped proofs for inventory/catalog/package/launch as required. Existing Xbox Live scopes and configurable XSTS relying party do not authorize arbitrary inventory APIs.

First request:

```json
{"kind":"request","protocol":{"major":1,"minor":0},"requestID":"req-001","command":"hello","params":{"client":"xodus-macos-app","clientVersion":"0.1.0"}}
```

```json
{"kind":"result","protocol":{"major":1,"minor":0},"requestID":"req-001","ok":true,"data":{"protocol":{"major":1,"minor":0},"backendVersion":"PROPOSED","runtimeFingerprint":"PROPOSED","capabilities":["inventory.snapshot","catalog.search","install.plan","jobs.snapshot","jobs.cancel","events.replay"],"sessionID":"session-001"}}
```

Major mismatch, missing required capabilities, wrong runtime pairing or failed hello disables integration with an explicit update instruction. Never assume pause, offline launch, delta updates or rollback just because an engine is present.

## Commands and ownership

| Command | Required input | Result/behavior |
| --- | --- | --- |
| `auth.begin` / `auth.cancel` / `auth.status` | account scope, request ID; cancellation target | Approved consent flow metadata/status only; credentials delivered to broker/Keychain, never events. Nonempty valid credential proof required. |
| `inventory.snapshot` | account scope, market, refresh policy | products + entitlement evidence; source, checkedAt, lastCompleteAt, completeness, cursor/error. Backend consumes all pages or explicitly marks partial. |
| `catalog.search` | query, PC platform, market, language, cursor | catalog candidates and editions; no invented ownership. Pagination cannot rewrite entitlement. |
| `product.detail` | product/edition ID, account scope | independent facets + provenance/time/fingerprint; selected package or explicit ambiguity. |
| `install.plan` | edition ID, architecture, language, destination | immutable expiring plan with exact package/version/runtime, storage calculation, authorization and consent requirements. |
| `jobs.enqueue` | plan ID, plan digest, idempotency key | durable job ID. Repeated key returns same job; changed payload conflicts. Rechecks authorization/capacity. |
| `jobs.pause/resume/cancel/retry` | job ID, expected revision | capability-gated mutations. Cancel acknowledges durable intent and later terminal outcome. Retry cannot bypass verification/authorization. |
| `jobs.snapshot` / `events.replay` | session ID, after sequence | durable snapshot with watermark, or ordered replay; retention miss requires snapshot. |
| `installed.snapshot` | managed registry scope | stable installation IDs with package, paths, version, paired runtime, save policy and health. |
| `game.launch` | installation ID, expected revision | supervised launch job, explicit access/runtime/file validation and eventual process outcome. |
| `game.update/rollback/remove` | installation ID + pinned plan/revision; consent | failure-safe jobs; default preserve saves; deletion limited to validated manifest-owned content. |
| `diagnostics.export` | bounded scope, redaction policy | previewable sanitized report, never raw tokens, signed URLs or account identity. |

## Typed result shape

Example data uses invented placeholders, not real product identifiers or working URLs:

```json
{
  "productID":"fixture-harbor",
  "editionID":"fixture-harbor-standard",
  "entitlement":{"kind":"purchase","source":"fixture","checkedAt":"2026-10-03T12:00:00Z","expiresAt":null},
  "installability":{"kind":"downloadable","packageID":"fixture-harbor-arm64","packageVersion":"1.0","reason":null},
  "compatibility":{"kind":"experimental","source":"fixture","checkedAt":"2026-10-03T12:00:00Z","os":"fixture-os","architecture":"arm64","runtimeFingerprint":"fixture-runtime"},
  "installation":{"kind":"notInstalled","installationID":null},
  "inventory":{"completeness":"partial","checkedAt":"2026-10-03T12:00:00Z","lastCompleteAt":null,"reason":"upstream page unavailable"}
}
```

Purchase, subscription, none, unknown never collapse. Subscription has optional expiry with an explicit unknown-expiry policy. Installability distinguishes downloadable, blocked and unknown; compatibility distinguishes verified, experimental, unsupported and unknown. A verified result is scoped to its OS/runtime fingerprint and expires/re-evaluates after changes. Local installation is independent.

Plans define integer `downloadBytes`, `expandedBytes`, `stagingBytes`, `rollbackBytes`, `runtimeBytes`, `reserveBytes`, `reclaimableManagedBytes`, `requiredFreeBytes`, `availableBytes`, exact destination volume, `expiresAt`, `planDigest`, authorization freshness and reasoned warnings. Formula accounts for already verified/reusable files without claiming block-level deltas. Negative/overflow sizes or mismatched digest are errors. Recheck at enqueue and allocation boundaries.

## Jobs, replay and cancellation

```json
{"kind":"event","protocol":{"major":1,"minor":0},"sessionID":"session-001","sequence":43,"requestID":"req-install","jobID":"job-001","revision":4,"event":"job.changed","data":{"state":"verifying","completedBytes":2048,"totalBytes":2048}}
```

Sequence is monotonically increasing within session; revision is monotonic per job. Persist terminal states and watermark transactionally. Duplicate events are ignored; gaps trigger replay; old session IDs trigger snapshot. A snapshot is an authoritative set at watermark, not a list to append. On retention expiry return `EVENTS_EXPIRED` and latest watermark. Apply snapshot first, then events strictly above its watermark. Never use bytes as an identity.

Allowed progression: queued -> downloading -> verifying -> extracting -> committing -> completed. Pause/resume only during supported phases; failure -> recoverable/permanent; cancellation -> cancelling -> cancelled (or completion won the commit race with explicit response). Cancellation request must be idempotent and must not erase an already committed installation. Retries preserve job identity/revision or explicitly link a replacement; no late progress revives terminal jobs.

## Explicit failures

```json
{"kind":"result","protocol":{"major":1,"minor":0},"requestID":"req-002","ok":false,"error":{"code":"INSUFFICIENT_SPACE","message":"More free space is required on the selected volume.","retryable":true,"details":{"requiredBytes":8192,"availableBytes":4096}}}
```

Required codes include `PROTOCOL_MISMATCH`, `CAPABILITY_MISSING`, `AUTH_CANCELLED`, `AUTH_EXPIRED`, `AUTH_INVALID`, `INVENTORY_PARTIAL`, `ACCESS_UNKNOWN`, `ACCESS_REVOKED`, `PACKAGE_AMBIGUOUS`, `PACKAGE_UNAVAILABLE`, `PLAN_EXPIRED`, `PLAN_CHANGED`, `INSUFFICIENT_SPACE`, `NETWORK_UNAVAILABLE`, `INTEGRITY_FAILED`, `RUNTIME_MISMATCH`, `UNSUPPORTED_CONFIGURATION`, `REVISION_CONFLICT`, `EVENTS_EXPIRED`, `CANCELLED`, `REGISTRY_RECOVERY_REQUIRED`, `LAUNCH_FAILED`, `INTERNAL_ERROR`. Diagnostic details are structured/redacted, never raw upstream responses.

Every request ID has exactly one terminal result; jobs continue through events. A transport EOF before terminal result is failure even with exit 0. Nonzero exit overrides apparent success until reconciled. Success must include the correct required result shape and durable state. Test interactive-output contamination, malformed/truncated frames, empty token proof, missing job completion, duplicate sequences, snapshot races and success-after-inner-error.

## Durable registry and updates

Registry schema has its own major/minor version and migration backups. Installation ID is stable; active and rollback versions store package digest, exact runtime pairing, managed manifests and separate save root. Journal records prepare/verify/commit phases; only verified atomic promotion changes active version. Fault-inject at each write/fsync/rename and reconcile on restart. Preserve previous active entry until the new one commits. Cleanup validates every path and refuses traversal, external symlinks or unexpected ownership.

Signed/versioned runtime manifests are independent of package authorization. Invalid signature/hash/version/capability is a hard stop. Unknown consumer API authorization, license or signing model blocks shipping this contract as a live service.
