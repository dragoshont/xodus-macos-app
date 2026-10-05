#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Neutral policy checks; no certificate, private key, Keychain or actual signing operation."""
from pathlib import Path
import tempfile
from signing_identity import IDENTIFIERS, compare, preflight, sign

fingerprint = "A" * 40
calls = []


def neutral(arguments):
    calls.append(arguments)
    if arguments[0] == "/usr/bin/security":
        return '  1) ' + fingerprint + ' "Neutral test identity"\n     1 valid identities found\n'
    return ""


def rejected(operation):
    try:
        operation()
    except ValueError:
        return
    raise AssertionError("Unsafe signing policy was accepted")


for identity in (None, "", "-", "Certificate name", "A" * 39, "A" * 41):
    calls.clear()
    rejected(lambda: preflight(identity, run=neutral))
    assert not calls
rejected(lambda: preflight(fingerprint, True, neutral))
assert preflight(local_ad_hoc=True, run=neutral) == "-"
rejected(lambda: preflight(fingerprint, run=lambda _: "0 valid identities found\n"))
assert preflight(fingerprint.lower(), run=neutral) == fingerprint
for kind, identifier in IDENTIFIERS.items():
    calls.clear()
    sign("/neutral/new-build", kind, fingerprint, run=neutral)
    signing = calls[1]
    assert signing[signing.index("--sign") + 1] == fingerprint
    assert signing[signing.index("--identifier") + 1] == identifier
    assert signing[signing.index("--requirements") + 1] == (
        '=designated => identifier "' + identifier + '" and certificate leaf = H"' + fingerprint + '"')
    assert calls[-1][1:4] == ["--verify", "--strict", "/neutral/new-build"]
calls.clear()
sign("/neutral/local-only", "app", local_ad_hoc=True, run=neutral)
assert all(call[0] != "/usr/bin/security" for call in calls)
assert calls[0][calls[0].index("--sign") + 1] == "-"

with tempfile.TemporaryDirectory(prefix="xodus-signing-neutral-") as temporary:
    first, second = Path(temporary).resolve() / "first", Path(temporary).resolve() / "second"
    first.write_bytes(b"Different neutral build one. Never executed.")
    second.write_bytes(b"Different neutral build two. Never executed.")
    identifier = IDENTIFIERS["cli"]
    requirement = 'identifier "' + identifier + '" and certificate leaf = H"' + fingerprint + '"'
    def metadata(arguments):
        if arguments[0] == "/usr/bin/security":
            return neutral(arguments)
        if "--display" in arguments:
            return "Identifier=" + identifier + "\ndesignated => " + requirement + "\n"
        return ""
    compare(first, second, "cli", fingerprint, metadata)
    for bad in ('identifier "wrong" and certificate leaf = H"' + fingerprint + '"',
                requirement + ' and cdhash H"' + "B" * 40 + '"',
                requirement.replace(fingerprint, "B" * 40)):
        def altered(arguments, bad=bad):
            return ("Identifier=" + identifier + "\ndesignated => " + bad + "\n"
                    if "--display" in arguments else metadata(arguments))
        rejected(lambda: compare(first, second, "cli", fingerprint, altered))
    second.write_bytes(first.read_bytes())
    rejected(lambda: compare(first, second, "cli", fingerprint, metadata))
assert all(call[1:3] == ["find-identity", "-v"] for call in calls if call[0] == "/usr/bin/security")
print("PASS explicit missing identity, fixed signer IDs, no fallback/provisioning/export, and neutral two-build requirement policy.")
