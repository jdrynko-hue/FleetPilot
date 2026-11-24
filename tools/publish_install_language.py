#!/usr/bin/env python3
"""Stage the single reviewed install page over the November 21 release."""
import argparse
from hashlib import sha256
import shutil
import subprocess
from pathlib import Path

from prepare_marketing_release import check_portal, check_references, inventory
from publish_approved_marketing import read_approval, verify_public
from publish_fleet_first_marketing import PREVIOUS_DIGEST, PREVIOUS_MANIFEST, release_contract

SOURCE = "8d18f2725e75bba012c48b1b63fcdb6df115a2a2"
PAGE = "install/index.html"
EXPECTED_PAGE = "65581c04e652e967ef3da0e8e52af0d6124885a48d88907e2d3d0e7e480f68f6"


def contract(repo):
    earlier = read_approval(repo / PREVIOUS_MANIFEST, PREVIOUS_DIGEST)
    baseline = release_contract(earlier)["files"]
    content = subprocess.check_output(
        ["git", "-C", repo, "show", f"{SOURCE}:web/{PAGE}"]
    )
    if sha256(content).hexdigest() != EXPECTED_PAGE:
        raise ValueError("Install page does not match the reviewed bytes")
    return {
        "files": {**baseline, PAGE: {"sha256": EXPECTED_PAGE, "size_bytes": len(content)}},
        "previous_pages": {PAGE: baseline[PAGE]},
        "package_sha256": "c310db9b7045a9fc89a0602eb2c2a2ceb393f8ca6ed1db10f448acfe4c5aff51",
    }, baseline, content


def prepare(baseline, output, expected, original, content):
    if inventory(baseline) != original:
        raise ValueError("Production baseline differs from the November 21 release")
    output.mkdir(parents=True, exist_ok=False)
    site = output / "site"
    rollback = output / "rollback"
    shutil.copytree(baseline, rollback)
    shutil.copytree(baseline, site)
    (site / PAGE).write_bytes(content)
    if inventory(site) != expected["files"] or inventory(rollback) != original:
        raise ValueError("Staged release or rollback inventory differs")
    check_references(site, PAGE)
    check_portal(site, expected["files"])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    stage = commands.add_parser("prepare")
    stage.add_argument("--baseline", type=Path, required=True)
    stage.add_argument("--output", type=Path, required=True)
    verify = commands.add_parser("verify")
    verify.add_argument("--phase", required=True, choices=("baseline", "release"))
    verify.add_argument("--attempts", type=int, required=True)
    verify.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    expected, original, content = contract(Path.cwd())
    if args.command == "prepare":
        prepare(args.baseline, args.output, expected, original, content)
        print("Verified 161 release files and 161 rollback files")
    else:
        print(verify_public(expected, args.phase, args.attempts, args.report))


if __name__ == "__main__":
    main()
