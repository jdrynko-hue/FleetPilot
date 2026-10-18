#!/usr/bin/env python3
"""Read-only checks for an assembled, *unpublished* Flotaryx release candidate.

Passing does not imply production Auth, billing, legal, or device readiness.
"""
from __future__ import annotations

import argparse
from html.parser import HTMLParser
from pathlib import Path
import re
from urllib.parse import parse_qs, urlsplit


PRIVATE_CREDENTIAL = re.compile(
    rb"(?:sk|rk)_(?:live|test)_[A-Za-z0-9]{8,}"
    rb"|sb_secret_[A-Za-z0-9_]{8,}"
    rb"|whsec_[A-Za-z0-9]{8,}"
)


class Page(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.bases: list[str | None] = []
        self.links: list[str] = []
        self.scripts: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        a = dict(attrs)
        if tag == "base":
            self.bases.append(a.get("href"))
        if tag == "a" and a.get("href"):
            self.links.append(a["href"])
        if tag == "script" and a.get("src"):
            self.scripts.append(a["src"])


def validate(site: Path) -> list[str]:
    issues: list[str] = []
    required = (
        "index.html", "CNAME", "app/index.html",
        "app/flutter_bootstrap.js", "app/main.dart.js",
    )
    for name in required:
        item = site / name
        if not item.is_file() or item.stat().st_size == 0:
            issues.append(f"Missing/empty artifact: {name}")
    if issues:
        return issues

    if (site / "CNAME").read_text(encoding="utf-8").strip() != "flotaryx.com":
        issues.append("CNAME must be flotaryx.com")

    home = Page()
    portal = Page()
    home.feed((site / "index.html").read_text(encoding="utf-8"))
    portal.feed((site / "app/index.html").read_text(encoding="utf-8"))
    if home.bases != ["/"]:
        issues.append("Landing page must have exactly one / base href")
    if portal.bases != ["/app/"]:
        issues.append("Flutter portal must have exactly one /app/ base href")
    if "flutter_bootstrap.js" not in portal.scripts:
        issues.append("Flutter portal does not load bootstrap script")

    links = [urlsplit(url) for url in home.links]
    portal_targets = {
        parse_qs(url.query).get("portal", [""])[0]
        for url in links if url.path == "/app/" and not url.netloc
    }
    for target in ("fleet", "garage", "search"):
        if target not in portal_targets:
            issues.append(f"Missing landing portal entry: {target}")
    for target in ("/privacy/", "/terms/"):
        if not any(url.path == target and not url.netloc for url in links):
            issues.append(f"Missing legal link: {target}")

    for item in site.rglob("*"):
        if not item.is_file() or item.suffix.lower() not in {
            ".html", ".js", ".json", ".txt", ".xml", ".css",
        }:
            continue
        if PRIVATE_CREDENTIAL.search(item.read_bytes()):
            issues.append(f"Possible private credential in: {item.relative_to(site)}")
    return issues


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("site", type=Path, help="Unpublished site assembly directory")
    args = parser.parse_args()
    if not args.site.is_dir():
        print("FAIL: Site assembly directory is missing")
        return 1
    issues = validate(args.site)
    for issue in issues:
        print(f"FAIL: {issue}")
    if issues:
        return 1
    print("PASS: release artifact paths, links, entrypoints and private credential scan")
    print("NOT VERIFIED: hosted Auth, Stripe E2E, tax/legal, backups, real phones")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
