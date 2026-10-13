"""Check the public Auth password rule without administrative credentials."""
import json
import urllib.error
import urllib.request

ENDPOINT = "https://wqhymmtiawfwjikdaujo.supabase.co/auth/v1/signup"
PUBLISHABLE_KEY = "sb_publishable_j638npcsGiRpQqYbVoz1Rg_qo4vA6tt"


def rejects_short_password(status, body):
    return (
        status == 422
        and isinstance(body, dict)
        and isinstance(body.get("weak_password"), dict)
        and "length" in body["weak_password"].get("reasons", [])
    )


def main():
    # The reserved .invalid domain cannot receive mail. This deliberately weak
    # value is test input, never an account credential. Reject before signup.
    payload = json.dumps({
        "email": "qa-password-policy@flotaryx.invalid",
        "password": "QAshort123!",
    }).encode()
    request = urllib.request.Request(ENDPOINT, data=payload, method="POST", headers={
        "apikey": PUBLISHABLE_KEY,
        "Content-Type": "application/json",
    })
    try:
        with urllib.request.urlopen(request, timeout=30):
            raise SystemExit("FAIL: Auth unexpectedly accepted the short-password request")
    except urllib.error.HTTPError as error:
        try:
            body = json.loads(error.read())
        except (ValueError, UnicodeError):
            raise SystemExit("FAIL: Auth returned an unreadable error response") from None
        if not rejects_short_password(error.code, body):
            # Do not print response bodies: unexpected responses could include
            # user information or credentials.
            raise SystemExit(f"FAIL: Auth did not enforce password length (HTTP {error.code})") from None
    except urllib.error.URLError:
        raise SystemExit("FAIL: Public Auth endpoint could not be reached") from None
    print("PASS: Public Auth rejected an 11-character password for insufficient length")


if __name__ == "__main__":
    main()
