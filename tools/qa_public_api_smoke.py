"""Read-only public-client checks for the fixed hosted QA API.

No signups, emails, sessions, fixture writes or deployment. This does not test
authenticated authorization and cannot authorize a release. Runtime results
must remain private; the CLI prints check names only, never response bodies.
"""
import argparse
import json
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import HTTPRedirectHandler, Request, build_opener

API = 'https://fyestmquqvkdebxxbcky.supabase.co'
ZERO = '00000000-0000-0000-0000-000000000000'
MAX_BODY = 65536


class SmokeFailure(Exception):
    pass


def validate_config(cfg):
    if not isinstance(cfg, dict) or set(cfg) != {'api', 'anon'} or cfg.get('api') != API:
        raise SmokeFailure('Requires the fixed QA API and a publishable key only')
    key = cfg['anon']
    if (not isinstance(key, str) or not key.startswith('sb_publishable_')
            or not 25 <= len(key) <= 512
            or any(c not in 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-' for c in key)):
        raise SmokeFailure('Invalid publishable key configuration')


class _NoRedirects(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise SmokeFailure('API redirects are not allowed')


def transport(cfg):
    opener = build_opener(_NoRedirects())

    def get(path):
        req = Request(API + path, method='GET', headers={
            'apikey': cfg['anon'], 'Accept': 'application/json',
            'User-Agent': 'Flotaryx-QA-ReadOnly-Smoke',
        })
        try:
            response = opener.open(req, timeout=15)
        except HTTPError as error:
            response = error
        except (URLError, TimeoutError, OSError):
            raise SmokeFailure('QA API transport failed') from None
        with response:
            body = response.read(MAX_BODY + 1)
            if len(body) > MAX_BODY:
                raise SmokeFailure('QA API response exceeds the safe limit')
            try:
                data = json.loads(body)
            except (ValueError, UnicodeDecodeError):
                raise SmokeFailure('QA API returned invalid JSON') from None
            return response.code, data

    return get


def run(cfg, get=None):
    validate_config(cfg)
    get = get or transport(cfg)
    passed = []

    status, data = get('/auth/v1/health')
    if status != 200 or not isinstance(data, dict):
        raise SmokeFailure('Auth health check failed')
    passed.append('Auth health')

    status, data = get('/rest/v1/rpc/garage_booking_discover?p_city=Flotaryx%20Smoke%20No%20Match')
    public_fields = {'workspace_id', 'name', 'city', 'country', 'time_zone', 'services'}
    if (status != 200 or not isinstance(data, list)
            or any(not isinstance(row, dict) or set(row) != public_fields for row in data)):
        raise SmokeFailure('Public directory contract check failed')
    passed.append('Public directory contract')

    reads = {
        'Owner profile denied': '/rest/v1/rpc/garage_booking_profile?p_workspace=' + ZERO,
        'Workshop inbox denied': '/rest/v1/rpc/garage_booking_shop_inbox?p_workspace=' + ZERO,
        'Customer bookings denied': '/rest/v1/rpc/garage_booking_my_requests',
        'Customer notifications denied': '/rest/v1/rpc/garage_booking_my_notifications',
        'Booking rows denied': '/rest/v1/garage_booking_requests?select=id&limit=1',
        'Booking events denied': '/rest/v1/garage_booking_events?select=id&limit=1',
        'Booking profiles denied': '/rest/v1/garage_booking_profiles?select=workspace_id&limit=1',
        'Notification rows denied': '/rest/v1/garage_booking_notifications?select=id&limit=1',
    }
    for label, path in reads.items():
        status, data = get(path)
        # A missing RPC/schema-cache entry or an unrelated gateway failure is
        # not proof of authorization. Require PostgreSQL privilege denial.
        if status not in (401, 403) or not isinstance(data, dict) or data.get('code') != '42501':
            raise SmokeFailure(label + ': expected an explicit privilege denial')
        passed.append(label)
    return passed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', required=True,
                        help='Private local JSON with api and anon; never commit runtime configuration')
    args = parser.parse_args()
    try:
        cfg = json.loads(Path(args.config).read_text())
        passed = run(cfg)
    except (SmokeFailure, ValueError, OSError):
        # Do not expose request headers, response data or credential-bearing
        # exception messages in logs that may later be shared.
        print('FAIL: QA public-client checks did not pass; inspect privately')
        return 1
    for label in passed:
        print('PASS: ' + label)
    print('Read-only checks only; authenticated and physical-device acceptance remain required')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
