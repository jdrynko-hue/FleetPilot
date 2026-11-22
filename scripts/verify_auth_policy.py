"""Verify Auth settings, with an explicit option to apply a bounded correction."""
import argparse
import json
import os
from pathlib import Path
import urllib.error
import urllib.request
from urllib.parse import urlsplit

PROJECT_REF = "wqhymmtiawfwjikdaujo"
APP_REDIRECT = "https://flotaryx.com/app/"
QA_PROJECT_REF = "fyestmquqvkdebxxbcky"
QA_CALLBACK_PATHS = ("/app/", "/booking-recovery-qa/")


def qa_redirects(callback):
    """Require an explicit private Sites return route, never a wildcard."""
    try:
        url = urlsplit(callback)
        valid = (url.scheme == "https" and url.hostname
                 and url.hostname.endswith(".chatgpt.site")
                 and url.netloc == url.hostname and url.path in QA_CALLBACK_PATHS
                 and not url.query and not url.fragment
                 and not any(c.isspace() or c in "*?#[\\]" for c in callback))
    except ValueError:
        valid = False
    if not valid:
        raise ValueError("QA requires an exact HTTPS Sites /app/ or /booking-recovery-qa/ callback")
    return (callback, *(callback + "?portal=" + portal
                        for portal in ("fleet", "garage", "customer", "search")))


def policy_patch(config, required_redirects=(APP_REDIRECT,)):
    minimum = config.get("password_min_length")
    if type(minimum) is not int or minimum < 1:
        raise ValueError("Auth password minimum is missing or invalid")
    redirects = config.get("uri_allow_list", "")
    if not isinstance(redirects, str):
        raise ValueError("Auth redirect list has an unexpected format")
    patch = {}
    if minimum < 12:
        patch["password_min_length"] = 12
    existing = [url.strip() for url in redirects.split(",")]
    missing = [url for url in required_redirects if url not in existing]
    if missing:
        patch["uri_allow_list"] = ",".join(filter(None, [redirects, *missing]))
    return patch


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true",
                        help="Apply the required production Auth policy corrections")
    parser.add_argument("--environment", choices=("production", "qa"), default="production")
    parser.add_argument("--qa-callback", action="append",
                        help="Exact reviewed HTTPS Sites return URL; repeat for each QA mount")
    parser.add_argument("--qa-redirect-file", type=Path,
                        help="Compare dashboard Redirect URLs offline, one URL per line")
    args = parser.parse_args(argv)
    required = (APP_REDIRECT,)
    project = PROJECT_REF
    if args.environment == "qa":
        if args.apply:
            parser.error("QA verification is read-only; --apply is not supported")
        if not args.qa_callback:
            parser.error("QA verification requires --qa-callback")
        try:
            required = tuple(dict.fromkeys(url for callback in args.qa_callback
                                           for url in qa_redirects(callback)))
        except ValueError as error:
            parser.error(str(error))
        project = QA_PROJECT_REF
    elif args.qa_callback is not None:
        parser.error("--qa-callback is only valid with --environment qa")
    if args.qa_redirect_file is not None:
        if args.environment != "qa" or sorted(urlsplit(url).path for url in args.qa_callback) != sorted(QA_CALLBACK_PATHS):
            parser.error("Offline comparison requires one QA callback for each mount")
        try:
            redirects = args.qa_redirect_file.read_text(encoding="utf-8-sig").splitlines()
        except (OSError, UnicodeError):
            parser.error("Could not read the QA redirect list as UTF-8")
        missing = set(required) - {url.strip() for url in redirects}
        if missing:
            raise SystemExit(f"Offline QA redirect comparison failed: {len(missing)} of {len(required)} exact entries missing")
        print(f"Offline QA redirect comparison: {len(required)} exact entries present")
        print("Live Auth settings and password policy unverified")
        return
    token = os.environ.get("SUPABASE_ACCESS_TOKEN")
    if not token:
        raise SystemExit("Missing existing SUPABASE_ACCESS_TOKEN repository secret")
    endpoint = f"https://api.supabase.com/v1/projects/{project}/config/auth"

    def request(method="GET", payload=None):
        data = None if payload is None else json.dumps(payload).encode()
        req = urllib.request.Request(endpoint, data=data, method=method, headers={
            "Authorization": "Bearer " + token,
            "Content-Type": "application/json",
        })
        try:
            with urllib.request.urlopen(req, timeout=30) as response:
                return json.load(response)
        except urllib.error.HTTPError as error:
            # Error bodies and config responses may contain credentials.
            raise SystemExit(f"Supabase Auth configuration request failed: HTTP {error.code}") from None

    before = request()
    patch = policy_patch(before, required)
    if patch and not args.apply:
        fields = ", ".join(sorted(patch))
        raise SystemExit(f"Auth policy verification failed for: {fields}")
    if patch:
        request("PATCH", patch)
    after = request() if patch else before
    if policy_patch(after, required):
        raise SystemExit("Auth password minimum or app redirect failed verification")
    print("Server password minimum:", after["password_min_length"])
    print("Exact required Auth return URLs present:", len(required))
    if patch:
        print("Auth policy fields patched:", ", ".join(sorted(patch)))


if __name__ == "__main__":
    main()
