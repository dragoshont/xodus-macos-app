# Controlled local shipping boundary

`XODUS_SHIPPING=1` selects a different SwiftPM source set, not a runtime demo
toggle. Fixture views/state, game illustrations/resources, synthetic core
install plans/jobs, exports, native check entrypoints and the authentication-host
check corpus are excluded. Live Library/Discover/Downloads and Account show
native state and actual management data. Unsupported game installation/play
does not get a simulated action. The nonshipping preview/test products remain
available for explicitly requested development.

Shipping ignores `XODUS_BACKEND_PATH` and remembered developer selection,
has no engine picker, rejects preview/test/development argv, and resolves only:

- `Contents/Resources/XodusEngine/xodus-cli`
- `Contents/MacOS/XodusAuthHost`
- `Contents/Resources/XodusAuthHost.json`

The repository's `ShippingPairPins.approved` is nil. This compiles, but management
and pure planning fail closed before any process. Packaging generates a
stage-only Swift pin table after independently approved sealed inputs and
separate signing. The table binds schema1, approved app commit/tree,
producer9ef/tree8b2f, signed engine/helper SHA256 and byte sizes, helper version1
and matching helper source. Runtime JSON, HELLO and ad-hoc signing alone cannot
create that approval.

## Operator trust chain

`tools/build_app.sh` requires the exact externally approved app commit/tree,
unsigned CLI SHA256/bytes, adjacent provenance SHA256/bytes and a new owned output
root. It refuses a dirty/mismatched source and does not overwrite an old app.
The provenance is hash-pinned before parsing. Duplicate keys, wrong source/tree,
nonrelease profile, unexpected features, incorrect architecture/target,
plaintext/debug/console feature changes or mismatched sealed identity reject
the input. These claims are accepted only under the operator's independent
external pins, not because the JSON asserts them.

The source producer is `9ef0f298481fb48840734b538e0f6d22e1c98ff3`,
tree `8b2f7abb54f91e347afe013eee18c93873b111a5`, containing the reviewed auth943
boundary. Required Cargo profile is opt3/debug0, no debug assertions/overflow
checks/test. Exact features are xodus/CLI empty, management live, native Keychain
and security-framework. The old e7/304 engine cannot satisfy this gate.

The copied unsigned engine is rehashed before signing. The separately signed
CLI/helper identities are new pins, not renamed unsigned hashes. Only then is
`ShippingPairPins.swift` generated and the launcher compiled in the isolated
source stage. The external package receipt records unsigned/provenance inputs,
signed identities, generated compiler pins and final resource/package inventory.
The final app sign is followed by deep verification, helper receipt/identity,
arm64 and C95/provider-resource checks, then the original unsigned inputs are
reverified. Signing/source generation is never performed on the current checkout
or a protected bundle.

Runtime admission requires canonical no-follow current-UID single-link regular
executables, non-group/world-writable files, exact sizes and SHA256; helper
metadata remains bounded/canonical and its source/version/hash must match
compiled pins. The management launch rechecks identity immediately before
execution; paired auth mutations also recheck. Pure planning performs the same
shipping pair gate and prelaunch engine check. No credential value is added to
argv, receipts or logs.

## Evidence and remaining gates

Neutral checks compile the shipping source, test nil/valid/missing/changed/
linked/source/version/size failures with an owned mock engine and no helper or
account operation, verify no shipping resource bundles contain illustrations/
private fixture corpora, and execute the shipping binary's rejected flags.
Startup delayed reconciliation tests protect a post-ready user query across
initial connection and reconnect; loading/error/cancelled/confirmed-zero remain
distinct.

This is a **controlled local operator-approved pair**, not a generic provenance
framework, DeveloperID release, notarized distribution or a successful Microsoft
login. New sealed CLI existence does not authorize packaging/launch. Source
review, exact native qualification, independent package checks, desktop ownership
and explicit launch approval remain separate. Credentials, MFA/consent and
Keychain interaction are human-only. Owned inventory, install/update and verified
gameplay remain unsupported rather than fabricated. No passkey capability or
biometric cause/fix is inferred from the Swift host or neutral tests.
