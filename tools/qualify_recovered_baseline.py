#!/usr/bin/env python3
"""Bind a complete public capture to independently retrieved CI artifact evidence.

The resulting version-2 baseline explicitly records recovery. It never claims
that the expired original ZIP was recovered or that publication is authorized.
"""
import argparse
import hashlib
import json
from pathlib import Path
import zipfile

import prepare_marketing_release as release
import recover_marketing_baseline as recovery


def read_json(path):
    return json.loads(Path(path).read_text(), object_pairs_hook=recovery.unique_object)


def source_aliases(evidence):
    source = {item["path"][4:]: item for item in evidence["source_web"]}
    result = {}
    for name, item in source.items():
        result[name] = (item, None)
        result["app/" + name] = (item, None)
    result["index.html"] = (source["index.html"], "/")
    result["app/index.html"] = (source["app/index.html"], "/app/")
    return result


def verify_source(site, evidence):
    aliases = source_aliases(evidence)
    for name, (item, base) in aliases.items():
        data = (site / name).read_bytes()
        if base:
            data = data.replace(('<base href="' + base + '">').encode(),
                                b'<base href="$FLUTTER_BASE_HREF">')
        blob = b"blob " + str(len(data)).encode() + b"\0" + data
        if (len(data) != item["size_bytes"]
                or hashlib.sha1(blob, usedforsecurity=False).hexdigest() != item["git_blob"]):
            raise release.PreparationError("Recovered bytes do not match deployed Git source: " + name)
    return len(aliases)


def qualify(*, capture, source_inventory, artifact_archive, artifact_sha256,
            capture_run, capture_artifact, output):
    capture, source_inventory, artifact_archive = map(
        Path, (capture, source_inventory, artifact_archive))
    output = Path(output)
    if output.exists() or output.is_symlink():
        raise release.PreparationError("Qualified manifest output already exists")
    if (not release.SHA256.fullmatch(artifact_sha256)
            or release.digest(artifact_archive) != artifact_sha256):
        raise release.PreparationError("Capture ZIP does not match independently retrieved artifact SHA-256")
    for identifier in (capture_run, capture_artifact):
        if type(identifier) is not int or identifier <= 0:
            raise release.PreparationError("Actual capture run and artifact identifiers are required")
    evidence = recovery.load_inventory(source_inventory)
    if (capture / "source-inventory.json").read_bytes() != source_inventory.read_bytes():
        raise release.PreparationError("Capture changed the independently retained original file list")
    expected_zip = {"capture-report.json", "capture-manifest.json", "source-inventory.json"}
    expected_zip.update("site/" + name for name in evidence["files"])
    with zipfile.ZipFile(artifact_archive) as archive:
        entries = [item for item in archive.infolist() if not item.is_dir()]
        if len(entries) != len(expected_zip) or {x.filename for x in entries} != expected_zip:
            raise release.PreparationError("Unexpected capture archive inventory")
        for entry in entries:
            recovery.file_path(entry.filename)
            local = capture / entry.filename
            if local.is_symlink() or not local.is_file() or entry.file_size > recovery.MAX_FILE_BYTES:
                raise release.PreparationError("Invalid extracted capture file")
            if hashlib.sha256(archive.read(entry)).hexdigest() != release.digest(local):
                raise release.PreparationError("Extracted bytes differ from the verified capture archive")
    report = read_json(capture / "capture-report.json")
    manifest = read_json(capture / "capture-manifest.json")
    if (report.get("status") != "CAPTURED_CURRENT_PRODUCTION_NOT_RELEASED"
            or report.get("failures") != []
            or report.get("original_archive_available") is not False
            or report.get("original_archive_recreated") is not False
            or report.get("same_bytes_in_two_complete_passes") is not True
            or report.get("publication_authorized") is not False
            or report.get("origin") != release.ORIGIN
            or report.get("deployment_run_id") != evidence["deployment_run_id"]
            or report.get("deployed_source_commit") != evidence["source_commit"]
            or report.get("captured_file_count") != len(evidence["files"])
            or report.get("original_archive_file_count") != len(evidence["files"])):
        raise release.PreparationError("Capture did not prove a complete stable snapshot")
    if (manifest.get("version") != 1
            or manifest.get("kind") != "flotaryx-current-production-capture"
            or manifest.get("origin") != release.ORIGIN
            or manifest.get("source_inventory_sha256") != release.digest(source_inventory)
            or not isinstance(manifest.get("files"), dict)
            or sorted(manifest["files"]) != evidence["files"]):
        raise release.PreparationError("Invalid capture manifest")
    site = capture / "site"
    actual = release.inventory(site)
    if sorted(actual) != evidence["files"]:
        raise release.PreparationError("Recovered site differs from original archive inventory")
    for name, item in manifest["files"].items():
        if {key: item.get(key) for key in ("sha256", "size_bytes")} != actual[name]:
            raise release.PreparationError("Recovered file checksum mismatch")
        if item.get("source") == "public_https":
            if item.get("last_modified") != evidence["public_last_modified"] or not item.get("etag"):
                raise release.PreparationError("Recovered file is not tied to the pinned deployment")
        elif item.get("source") != "deployed_git_cname" or name not in ("CNAME", "app/CNAME"):
            raise release.PreparationError("Unapproved recovery source")
    source_count = verify_source(site, evidence)
    if report.get("source_verified_file_count") != source_count:
        raise release.PreparationError("Source verification count mismatch")
    release.check_portal(site, actual)
    qualified = {
        "version": 2,
        "kind": "flotaryx-recovered-production-baseline",
        "origin": release.ORIGIN, "repository": release.REPOSITORY,
        "provenance": {
            "deployment_status": "success",
            "source_commit": evidence["source_commit"],
            "deployment_run_id": evidence["deployment_run_id"],
            "artifact_id": evidence["artifact_id"],
            "original_archive_sha256": evidence["original_archive_sha256"],
            "original_archive_available": False,
            "original_archive_recreated": False,
            "capture_run_id": capture_run,
            "capture_artifact_id": capture_artifact,
            "capture_artifact_sha256": artifact_sha256,
            "source_inventory_sha256": release.digest(source_inventory),
            "capture_manifest_sha256": release.digest(capture / "capture-manifest.json"),
            "captured_at": report["completed_at"],
            "archive_file_count": len(actual),
            "source_verified_file_count": source_count,
            "same_bytes_in_two_complete_passes": True,
        },
        "files": actual,
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    release.write_json(output, qualified)
    # Use the normal baseline reader too, so both contract paths share checks.
    release.read_manifest(output, release.digest(output))
    return {"manifest": str(output), "sha256": release.digest(output),
            "files": len(actual), "app_files": sum(x.startswith("app/") for x in actual),
            "source_verified_files": source_count, "original_archive_recreated": False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for key in ("capture", "source-inventory", "artifact-archive", "artifact-sha256", "output"):
        parser.add_argument("--" + key, required=True)
    parser.add_argument("--capture-run", type=int, required=True)
    parser.add_argument("--capture-artifact", type=int, required=True)
    args = parser.parse_args()
    try:
        result = qualify(**vars(args))
    except (release.PreparationError, recovery.CaptureError, OSError,
            ValueError, zipfile.BadZipFile, KeyError) as error:
        parser.exit(1, "HOLD: " + str(error) + "\n")
    print(json.dumps(result, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()

