#!/usr/bin/env python3
"""Recover a complete published snapshot using an independently retained tar list.

Read-only HTTPS GETs to flotaryx.com. No Flutter build, database, Auth, payment,
deployment or arbitrary URL input. The original archive is not recreated.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import time
from urllib.error import HTTPError, URLError
from urllib.parse import urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener

ORIGIN = "https://flotaryx.com"
REPOSITORY = "jdrynko-hue/FleetPilot"
MAX_FILE_BYTES = 32 * 1024 * 1024
MAX_TOTAL_BYTES = 256 * 1024 * 1024
MAX_FILES = 1000
HEX40 = re.compile(r"^[0-9a-f]{40}$")
HEX64 = re.compile(r"^[0-9a-f]{64}$")


class CaptureError(ValueError):
    pass


def file_path(value):
    if (not isinstance(value, str) or not re.fullmatch(r"[A-Za-z0-9_./-]+", value)
            or value.startswith("/") or value.endswith("/")
            or any(part in ("", ".", "..") for part in value.split("/"))):
        raise CaptureError("Unsafe archive path")
    return value


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise CaptureError("Duplicate inventory key")
        result[key] = value
    return result


def load_inventory(path):
    data = json.loads(Path(path).read_text(), object_pairs_hook=unique_object)
    if (not isinstance(data, dict) or data.get("version") != 1
            or data.get("kind") != "flotaryx-deployment-archive-inventory"
            or data.get("repository") != REPOSITORY or data.get("origin") != ORIGIN
            or data.get("deployment_status") != "success"
            or data.get("original_archive_available") is not False):
        raise CaptureError("Unexpected deployment inventory contract")
    if not HEX40.fullmatch(data.get("source_commit", "")):
        raise CaptureError("An immutable deployed source commit is required")
    if not HEX64.fullmatch(data.get("original_archive_sha256", "")):
        raise CaptureError("Original archive digest evidence is required")
    for key in ("deployment_run_id", "build_job_id", "artifact_id"):
        if type(data.get(key)) is not int or data[key] <= 0:
            raise CaptureError("Invalid deployment evidence identifier")
    if not isinstance(data.get("public_last_modified"), str):
        raise CaptureError("Pinned public deployment date is required")
    files = data.get("files")
    if (not isinstance(files, list) or not 1 <= len(files) <= MAX_FILES
            or files != sorted(set(files))):
        raise CaptureError("A complete unique sorted archive inventory is required")
    for name in files:
        file_path(name)
    required = {"CNAME", "index.html", "start/index.html", "install/index.html",
                "app/index.html", "app/flutter_bootstrap.js", "app/main.dart.js",
                "app/manifest.json", "app/flutter_service_worker.js"}
    if not required.issubset(files):
        raise CaptureError("Required original website entries are missing")
    source = data.get("source_web")
    if not isinstance(source, list) or not source:
        raise CaptureError("Deployed source blob evidence is required")
    names = set()
    for entry in source:
        if not isinstance(entry, dict):
            raise CaptureError("Invalid source entry")
        name = file_path(entry.get("path"))
        if (not name.startswith("web/") or name in names
                or not HEX40.fullmatch(entry.get("git_blob", ""))
                or type(entry.get("size_bytes")) is not int
                or entry["size_bytes"] < 0):
            raise CaptureError("Invalid source blob evidence")
        names.add(name)
    return data


def git_read(repo, *args):
    result = subprocess.run(["git", "-C", str(repo), *args],
                            capture_output=True, check=False)
    if result.returncode:
        raise CaptureError("Cannot read the pinned deployed Git object")
    return result.stdout


def source_expectations(repo, inventory):
    commit = inventory["source_commit"]
    if git_read(repo, "rev-parse", "HEAD").decode().strip() != commit:
        raise CaptureError("Deployed source checkout has the wrong commit")
    sources = {}
    for entry in inventory["source_web"]:
        content = git_read(repo, "show", commit + ":" + entry["path"])
        blob = b"blob " + str(len(content)).encode() + b"\0" + content
        if (len(content) != entry["size_bytes"]
                or hashlib.sha1(blob, usedforsecurity=False).hexdigest() != entry["git_blob"]):
            raise CaptureError("Deployed source blob differs from archive evidence")
        sources[entry["path"][4:]] = content
    if "app/index.html" not in sources or "index.html" not in sources:
        raise CaptureError("Missing source entrypoints")
    expected = {}
    for name, content in sources.items():
        expected[name] = content
        expected["app/" + name] = content
    expected["index.html"] = sources["index.html"].replace(
        b'<base href="$FLUTTER_BASE_HREF">', b'<base href="/">')
    expected["app/index.html"] = sources["app/index.html"].replace(
        b'<base href="$FLUTTER_BASE_HREF">', b'<base href="/app/">')
    if not set(expected).issubset(inventory["files"]):
        raise CaptureError("Source files are absent from the original tar inventory")
    return expected


def allowed_response_paths(name):
    result = {"/" + file_path(name)}
    if name == "index.html":
        result.add("/")
    elif name.endswith("/index.html"):
        result.add("/" + name[:-10])
    return result


class SameFileRedirect(HTTPRedirectHandler):
    def __init__(self, name):
        self.paths = allowed_response_paths(name)

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        parts = urlsplit(newurl)
        if (parts.scheme != "https" or parts.netloc != "flotaryx.com"
                or parts.path not in self.paths or parts.query or parts.fragment):
            raise CaptureError("Redirect outside the exact public file was rejected")
        return super().redirect_request(req, fp, code, msg, headers, newurl)


@dataclass(frozen=True)
class Captured:
    content: bytes
    etag: str
    last_modified: str
    source: str = "public_https"


def fetch_public_file(name, last_modified):
    name = file_path(name)
    request = Request(ORIGIN + "/" + name, headers={
        "Accept-Encoding": "identity",
        "Cache-Control": "no-cache",
        "User-Agent": "Flotaryx-owner-snapshot/1.0",
    }, method="GET")
    opener = build_opener(SameFileRedirect(name))
    for attempt in range(3):
        try:
            with opener.open(request, timeout=20) as response:
                final = urlsplit(response.url)
                if (response.status != 200 or final.scheme != "https"
                        or final.netloc != "flotaryx.com"
                        or final.path not in allowed_response_paths(name)
                        or final.query or final.fragment):
                    raise CaptureError("Unexpected public file response")
                if response.headers.get("Content-Encoding", "identity") != "identity":
                    raise CaptureError("Encoded bytes cannot be used as the original file")
                actual_date = response.headers.get("Last-Modified", "")
                etag = response.headers.get("ETag", "")
                if actual_date != last_modified or not etag:
                    raise CaptureError("Public deployment date or ETag changed")
                content = response.read(MAX_FILE_BYTES + 1)
                if len(content) > MAX_FILE_BYTES:
                    raise CaptureError("Public file exceeds the bounded capture size")
                length = response.headers.get("Content-Length")
                if length is not None and int(length) != len(content):
                    raise CaptureError("Truncated public file")
                prefix = content.lstrip()[:80].lower()
                if not name.endswith(".html") and (
                        prefix.startswith(b"<!doctype html") or prefix.startswith(b"<html")):
                    raise CaptureError("HTML error page returned in place of an asset")
                return Captured(content, etag, actual_date)
        except HTTPError as error:
            if error.code < 500 or attempt == 2:
                raise
        except (URLError, TimeoutError, OSError):
            if attempt == 2:
                raise
        time.sleep(0.5 * (attempt + 1))
    raise CaptureError("Public read failed")


def capture_file(name, expected_date, expected_source):
    try:
        value = fetch_public_file(name, expected_date)
    except HTTPError as error:
        # CNAME is deployment metadata and Pages can decline to serve it.
        # Its exact original bytes are independently pinned in the Git source.
        if error.code == 404 and name in ("CNAME", "app/CNAME") and name in expected_source:
            value = Captured(expected_source[name], "", "", "deployed_git_cname")
        else:
            raise
    if name in expected_source and value.content != expected_source[name]:
        raise CaptureError("Published file differs from its pinned deployed source")
    return value


def fingerprint(value):
    return {
        "sha256": hashlib.sha256(value.content).hexdigest(),
        "size_bytes": len(value.content),
        "etag": value.etag,
        "last_modified": value.last_modified,
        "source": value.source,
    }


def verify_second_capture(first, second):
    if fingerprint(first) != fingerprint(second):
        raise CaptureError("The public file changed between capture passes")


def write_json(path, value):
    Path(path).write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def capture(inventory_path, deployed_source, output):
    evidence = load_inventory(inventory_path)
    expected_source = source_expectations(deployed_source, evidence)
    output = Path(output)
    if output.exists() or output.is_symlink():
        raise CaptureError("Capture output already exists")
    output.mkdir(parents=True)
    partial = output / "incomplete-files"
    partial.mkdir()
    started = datetime.now(timezone.utc).isoformat()
    captured, failures = {}, []

    def read(name):
        return capture_file(name, evidence["public_last_modified"], expected_source)

    with ThreadPoolExecutor(max_workers=4) as pool:
        futures = {pool.submit(read, name): name for name in evidence["files"]}
        total = 0
        for future in as_completed(futures):
            name = futures[future]
            try:
                value = future.result()
                total += len(value.content)
                if total > MAX_TOTAL_BYTES:
                    raise CaptureError("Complete capture exceeds the bounded size")
                destination = partial / name
                destination.parent.mkdir(parents=True, exist_ok=True)
                destination.write_bytes(value.content)
                captured[name] = value
            except (CaptureError, HTTPError, URLError, TimeoutError, OSError, ValueError) as error:
                failures.append({"path": name, "error": str(error)[:300]})

    if not failures:
        with ThreadPoolExecutor(max_workers=4) as pool:
            futures = {pool.submit(read, name): name for name in evidence["files"]}
            for future in as_completed(futures):
                name = futures[future]
                try:
                    verify_second_capture(captured[name], future.result())
                except (CaptureError, HTTPError, URLError, TimeoutError, OSError, ValueError) as error:
                    failures.append({"path": name, "pass": 2, "error": str(error)[:300]})

    report = {
        "version": 1,
        "status": "INCOMPLETE_CAPTURE" if failures else "CAPTURED_CURRENT_PRODUCTION_NOT_RELEASED",
        "origin": ORIGIN,
        "started_at": started,
        "completed_at": datetime.now(timezone.utc).isoformat(),
        "original_archive_available": False,
        "original_archive_recreated": False,
        "deployment_run_id": evidence["deployment_run_id"],
        "deployed_source_commit": evidence["source_commit"],
        "original_archive_file_count": len(evidence["files"]),
        "captured_file_count": len(captured),
        "source_verified_file_count": len(set(captured) & set(expected_source)),
        "same_bytes_in_two_complete_passes": not failures,
        "publication_authorized": False,
        "failures": sorted(failures, key=lambda x: x["path"]),
    }
    write_json(output / "capture-report.json", report)
    shutil.copyfile(inventory_path, output / "source-inventory.json")
    if failures:
        raise CaptureError("Incomplete snapshot; see capture-report.json")
    if sorted(captured) != evidence["files"]:
        raise CaptureError("Capture inventory differs from the independent archive list")
    write_json(output / "capture-manifest.json", {
        "version": 1,
        "kind": "flotaryx-current-production-capture",
        "origin": ORIGIN,
        "source_inventory_sha256": hashlib.sha256(Path(inventory_path).read_bytes()).hexdigest(),
        "files": {name: fingerprint(captured[name]) for name in sorted(captured)},
    })
    partial.rename(output / "site")
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--inventory", required=True)
    parser.add_argument("--deployed-source", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    try:
        report = capture(args.inventory, args.deployed_source, args.output)
    except (CaptureError, OSError, UnicodeError, json.JSONDecodeError) as error:
        parser.exit(1, "HOLD: " + str(error) + "\n")
    print(json.dumps(report, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()

