#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Explicit local signing policy; never provision, unlock or export a Keychain identity."""
import argparse
import re
import shutil
import subprocess
import sys
from pathlib import Path
from shipping_pair import owned_bytes, require

IDENTIFIERS = {"app": "io.github.dragoshont.xodus",
               "cli": "io.github.dragoshont.xodus.cli",
               "helper": "io.github.dragoshont.xodus.auth-host"}


def command(arguments):
    result = subprocess.run(arguments, capture_output=True, text=True, timeout=30)
    require(result.returncode == 0, "Signing command failed; no ad-hoc fallback or Keychain alteration performed")
    require(len(result.stdout) + len(result.stderr) <= 65536, "Signing metadata exceeds its bound")
    return result.stdout + result.stderr


def preflight(identity=None, local_ad_hoc=False, run=command):
    require(bool(identity) != local_ad_hoc,
            "Supply an OS Keychain code-signing identity, or explicitly select local-ad-hoc; no default fallback")
    if local_ad_hoc:
        return "-"
    require(re.fullmatch(r"[0-9a-fA-F]{40}", identity) is not None,
            "Signing identity must be an exact public certificate SHA1 fingerprint, not a name or private key")
    fingerprint = identity.upper()
    available = run(["/usr/bin/security", "find-identity", "-v", "-p", "codesigning"])
    valid = re.findall(r'^\s*\d+\)\s+([0-9A-Fa-f]{40})\s+"[^"\n]*"\s*$', available, re.MULTILINE)
    require(fingerprint in {value.upper() for value in valid},
            "Supplied OS Keychain code-signing identity is unavailable; human-approved provisioning is required")
    return fingerprint


def sign(path, kind, identity=None, local_ad_hoc=False, run=command):
    signer = preflight(identity, local_ad_hoc, run)
    arguments = ["/usr/bin/codesign", "--force", "--sign", signer,
                 "--identifier", IDENTIFIERS[kind], "--timestamp=none"]
    if not local_ad_hoc:
        # Bind the fixed identifier to the supplied certificate, not this build's cdhash.
        arguments += ["--requirements", '=designated => identifier "' + IDENTIFIERS[kind]
                      + '" and certificate leaf = H"' + signer + '"']
    run(arguments + [str(path)])
    run(["/usr/bin/codesign", "--verify", "--strict", str(path)])


def compare(first, second, kind, identity, run=command):
    signer = preflight(identity, run=run)
    first_record, _ = owned_bytes(first)
    second_record, _ = owned_bytes(second)
    require(first_record["sha256"] != second_record["sha256"],
            "Designated-requirement comparison requires two different signed builds")
    requirements = []
    for path in (first, second):
        run(["/usr/bin/codesign", "--verify", "--strict", str(path)])
        metadata = run(["/usr/bin/codesign", "--display", "--requirements", "-", "--verbose=2", str(path)])
        identifiers = re.findall(r"^Identifier=(.+)$", metadata, re.MULTILINE)
        designated = re.findall(r"^designated => (.+)$", metadata, re.MULTILINE)
        require(identifiers == [IDENTIFIERS[kind]] and len(designated) == 1,
                "Expected one fixed signing identifier and designated requirement")
        requirement = designated[0]
        require("cdhash" not in requirement.lower()
                and re.fullmatch(r'identifier "' + re.escape(IDENTIFIERS[kind])
                                 + r'" and certificate leaf = H"' + signer + r'"',
                                 requirement, re.IGNORECASE) is not None,
                "Requirement must bind only the fixed identifier and supplied certificate")
        requirements.append(requirement)
    require(requirements[0] == requirements[1], "Different builds have different designated requirements")


def reuse_cli(source, destination, digest, size):
    owned_bytes(source, digest, size)
    command(["/usr/bin/codesign", "--verify", "--strict", str(source)])
    require(not Path(destination).exists(), "CLI reuse destination must be new")
    shutil.copyfile(source, destination)
    Path(destination).chmod(0o755)
    owned_bytes(source, digest, size)
    owned_bytes(destination, digest, size)
    command(["/usr/bin/codesign", "--verify", "--strict", str(destination)])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    operations = parser.add_subparsers(dest="operation", required=True)
    for name in ("preflight", "sign", "compare"):
        operation = operations.add_parser(name)
        operation.add_argument("--identity")
        if name != "compare":
            operation.add_argument("--local-ad-hoc", action="store_true")
        if name != "preflight":
            operation.add_argument("--kind", choices=IDENTIFIERS, required=True)
        if name == "sign":
            operation.add_argument("--path", required=True)
        if name == "compare":
            operation.add_argument("--first", required=True)
            operation.add_argument("--second", required=True)
    reuse = operations.add_parser("reuse-cli")
    for name in ("source", "destination", "hash"):
        reuse.add_argument("--" + name, required=True)
    reuse.add_argument("--bytes", type=int, required=True)
    args = parser.parse_args()
    require(sys.platform == "darwin", "Actual signing and reuse require an approved macOS stage")
    if args.operation == "preflight":
        preflight(args.identity, args.local_ad_hoc)
    elif args.operation == "sign":
        sign(args.path, args.kind, args.identity, args.local_ad_hoc)
    elif args.operation == "compare":
        compare(args.first, args.second, args.kind, args.identity)
        print("Different signed builds have the same fixed certificate-bound designated requirement.")
    else:
        reuse_cli(args.source, args.destination, args.hash, args.bytes)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        raise SystemExit("Signing policy rejected: " + str(error))
