"""Verify Auth settings, with an explicit option to apply a bounded correction."""
import argparse
import json
import os
import urllib.error
import urllib.request

PROJECT_REF = "wqhymmtiawfwjikdaujo"
APP_REDIRECT = "https://flotaryx.com/app/"


def policy_patch(config):
    minimum = config.get("password_min_length")
    if type(minimum) is not int or minimum < 1:
        raise ValueError("Auth password minimum is missing or invalid")
    redirects = config.get("uri_allow_list", "")
    if not isinstance(redirects, str):
        raise ValueError("Auth redirect list has an unexpected format")
    patch = {}
    if minimum < 12:
        patch["password_min_length"] = 12
    if APP_REDIRECT not in [url.strip() for url in redirects.split(",")]:
        patch["uri_allow_list"] = ",".join(filter(None, [redirects, APP_REDIRECT]))
    return patch


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true",
                        help="Apply the required production Auth policy corrections")
    args = parser.parse_args(argv)
    token = os.environ.get("SUPABASE_ACCESS_TOKEN")
    if not token:
        raise SystemExit("Missing existing SUPABASE_ACCESS_TOKEN repository secret")
    endpoint = f"https://api.supabase.com/v1/projects/{PROJECT_REF}/config/auth"

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
    patch = policy_patch(before)
    if patch and not args.apply:
        fields = ", ".join(sorted(patch))
        raise SystemExit(f"Auth policy verification failed for: {fields}")
    if patch:
        request("PATCH", patch)
    after = request() if patch else before
    if policy_patch(after):
        raise SystemExit("Auth password minimum or app redirect failed verification")
    print("Server password minimum:", after["password_min_length"])
    print("Exact Flotaryx app recovery redirect allowed: true")
    if patch:
        print("Auth policy fields patched:", ", ".join(sorted(patch)))


if __name__ == "__main__":
    main()
