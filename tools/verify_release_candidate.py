#!/usr/bin/env python3
"""Read-only checks for an assembled, *unpublished* Flotaryx release candidate.

Passing does not imply production Auth, billing, legal, or device readiness.
"""
from __future__ import annotations

import argparse
from html.parser import HTMLParser
import json
from pathlib import Path
import re
from urllib.parse import parse_qs, urlsplit


PRIVATE_CREDENTIAL = re.compile(
    rb"(?:sk|rk)_(?:live|test)_[A-Za-z0-9]{8,}"
    rb"|sb_secret_[A-Za-z0-9_]{8,}"
    rb"|whsec_[A-Za-z0-9]{8,}"
    rb"|pk_live_[A-Za-z0-9]{8,}"
)


class Page(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.bases: list[str | None] = []
        self.links: list[str] = []
        self.scripts: list[str] = []
        self.manifests: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        a = dict(attrs)
        if tag == "base":
            self.bases.append(a.get("href"))
        if tag == "a" and a.get("href"):
            self.links.append(a["href"])
        if tag == "script" and a.get("src"):
            self.scripts.append(a["src"])
        if tag == "link" and "manifest" in (a.get("rel") or "").split() and a.get("href"):
            self.manifests.append(a["href"])


def validate(site: Path) -> list[str]:
    issues: list[str] = []
    required = (
        "index.html", "CNAME", "app/index.html",
        "app/flutter_bootstrap.js", "app/main.dart.js", "app/manifest.json",
    )
    # Never inspect linked content that could point outside the build root.
    for item in site.rglob("*"):
        if item.is_symlink():
            issues.append(f"Symlink must not be published: {item.relative_to(site)}")
    if issues:
        return issues
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
    if portal.manifests != ["manifest.json"]:
        issues.append("Flutter portal must link its /app/ manifest.json exactly once")

    # The PWA manifest must resolve under /app/ on mobile devices.
    try:
        manifest = json.loads((site / "app/manifest.json").read_text(encoding="utf-8"))
        if not isinstance(manifest, dict):
            raise ValueError("manifest root is not an object")
    except (ValueError, UnicodeDecodeError) as exc:
        issues.append(f"Invalid PWA manifest: {exc}")
    else:
        for name in ("id", "start_url", "scope"):
            if manifest.get(name) != "/app/":
                issues.append(f"PWA {name} must be /app/")
        icons = manifest.get("icons")
        if not isinstance(icons, list):
            issues.append("PWA icons must be a list")
        else:
            sizes = set()
            for icon in icons:
                if not isinstance(icon, dict):
                    issues.append("Invalid PWA icon descriptor")
                    continue
                src = icon.get("src")
                size = icon.get("sizes")
                if (not isinstance(src, str) or not src.startswith("icons/")
                    or ".." in Path(src).parts or urlsplit(src).scheme
                    or "?" in src or "#" in src):
                    issues.append("PWA icon has an unsafe or invalid path")
                    continue
                icon_path = site / "app" / src
                if not icon_path.is_file() or icon_path.stat().st_size == 0:
                    issues.append(f"Missing PWA icon: {src}")
                if isinstance(size, str):
                    sizes.add(size)
            for size in ("192x192", "512x512"):
                if size not in sizes:
                    issues.append(f"PWA lacks icon size {size}")

    links = [urlsplit(url) for url in home.links]
    portal_targets = {
        parse_qs(url.query).get("portal", [""])[0]
        for url in links if url.path == "/app/" and not url.netloc and not url.scheme
    }
    for target in ("fleet", "garage", "search"):
        if target not in portal_targets:
            issues.append(f"Missing landing portal entry: {target}")
    for target in ("/privacy/", "/terms/"):
        if not any(url.path == target and not url.netloc and not url.scheme for url in links):
            issues.append(f"Missing legal link: {target}")
        legal_page = site / target.lstrip("/") / "index.html"
        if not legal_page.is_file() or legal_page.stat().st_size == 0:
            issues.append(f"Missing/empty linked legal page: {target}")

    # Validate shipping of all 24 legal pages, not legal sufficiency.
    legal_languages = ("en", "pl", "de", "sk", "cs", "hu", "ro",
                       "es", "fr", "it", "uk", "pt")
    for language in legal_languages:
        for document in ("terms", "privacy"):
            rel = f"legal/{language}/{document}/index.html"
            legal_path = site / rel
            if not legal_path.is_file() or legal_path.stat().st_size == 0:
                issues.append(f"Missing/empty localized legal page: {rel}")
                continue
            content = legal_path.read_text(encoding="utf-8")
            if "<title>" not in content or "support@flotaryx.com" not in content:
                issues.append(f"Localized legal page lacks title/contact: {rel}")

    for item in site.rglob("*"):
        if not item.is_file():
            continue
        relative = item.relative_to(site)
        name = item.name.lower()
        if (name.startswith(".env") or name in {"id_rsa", "id_ed25519"}
            or item.suffix.lower() in {".pem", ".p12", ".pfx", ".key"}):
            issues.append(f"Private-looking file must not be published: {relative}")
        if item.suffix.lower() not in {
            ".html", ".js", ".mjs", ".cjs", ".map", ".json", ".txt",
            ".xml", ".css", ".svg", ".yml", ".yaml", ".toml", ".env",
        }:
            continue
        if PRIVATE_CREDENTIAL.search(item.read_bytes()):
            issues.append(f"Possible private credential in: {relative}")
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
