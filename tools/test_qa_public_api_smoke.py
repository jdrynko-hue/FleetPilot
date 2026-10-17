"""Offline regressions for the QA public-client gate; no hosted calls."""
import contextlib
import io
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from urllib.request import Request

from qa_public_api_smoke import API, MAX_BODY, SmokeFailure, _NoRedirects, main, run, transport

CONFIG = {'api': API, 'anon': 'sb_publishable_offline_fixture_only'}


class PublicApiSmokeTest(unittest.TestCase):
    def call(self, patch=None, cfg=None):
        requests = []

        def get(path):
            requests.append(path)
            if patch:
                response = patch(path)
                if response is not None:
                    return response
            if path == '/auth/v1/health':
                return 200, {'name': 'GoTrue'}
            if 'garage_booking_discover' in path:
                return 200, []
            return 401, {'code': '42501'}

        return run(CONFIG if cfg is None else cfg, get), requests

    def test_all_checks_are_fixed_read_paths(self):
        passed, paths = self.call()
        self.assertEqual(len(passed), 10)
        self.assertEqual(len(paths), 10)
        self.assertTrue(all(path.startswith(('/auth/v1/health', '/rest/v1/')) for path in paths))
        self.assertFalse(any(word in path for path in paths for word in
                             ('signup', '/token', '_request_once', '_cancel', '_configure')))

    def test_production_and_alternate_origins_never_make_requests(self):
        for origin in ('https://wqhymmtiawfwjikdaujo.supabase.co',
                       'https://example.test', API + '/', API + '@example.test'):
            with self.subTest(origin=origin), self.assertRaises(SmokeFailure):
                self.call(cfg=CONFIG | {'api': origin})

    def test_sessions_passwords_and_extra_fields_are_rejected(self):
        for key in ('jwt', 'password', 'access_token', 'refresh_token', 'headers'):
            with self.subTest(key=key), self.assertRaises(SmokeFailure):
                self.call(cfg=CONFIG | {key: 'never-use'})

    def test_secret_legacy_and_header_injection_keys_are_rejected(self):
        for key in ('sb_secret_private_fixture', 'eyJlegacy.jwt.token',
                    'sb_publishable_fake\nAuthorization: bad', '', None):
            with self.subTest(key=key), self.assertRaises(SmokeFailure):
                self.call(cfg=CONFIG | {'anon': key})

    def test_invalid_config_shapes_are_rejected(self):
        for cfg in ({}, [], None, 'config'):
            with self.subTest(cfg=cfg), self.assertRaises(SmokeFailure):
                run(cfg, lambda _: self.fail('must validate before network'))

    def test_invalid_key_cannot_turn_all_denials_into_a_pass(self):
        with self.assertRaises(SmokeFailure):
            self.call(patch=lambda _: (401, {'code': '42501'}))

    def test_missing_rpc_or_schema_cache_is_not_privilege_denial(self):
        for code in ('PGRST202', 'PGRST301', '42P01', 'XX000'):
            with self.subTest(code=code), self.assertRaises(SmokeFailure):
                self.call(patch=lambda path: (401, {'code': code}) if 'garage_booking_profile?' in path else None)

    def test_empty_table_success_still_fails_direct_access_gate(self):
        with self.assertRaises(SmokeFailure):
            self.call(patch=lambda path: (200, []) if '/garage_booking_requests?' in path else None)

    def test_missing_route_server_error_and_html_fail_closed(self):
        for response in ((404, {'code': '42501'}), (500, {'code': '42501'}), (401, '<html>')):
            with self.subTest(response=response), self.assertRaises(SmokeFailure):
                self.call(patch=lambda path: response if 'garage_booking_profile?' in path else None)

    def test_public_directory_must_not_add_private_fields(self):
        row = dict(workspace_id='fake', name='Synthetic', city='Synthetic',
                   country='GB', time_zone='Europe/London', services=['brakes'])
        self.call(patch=lambda path: (200, [row]) if 'garage_booking_discover' in path else None)
        with self.assertRaises(SmokeFailure):
            self.call(patch=lambda path: (200, [row | {'customer_email': 'private'}])
                      if 'garage_booking_discover' in path else None)

    def test_redirect_never_forwards_publishable_key(self):
        with self.assertRaises(SmokeFailure):
            _NoRedirects().redirect_request(Request(API), None, 302, '', {}, 'https://example.test')

    def test_transport_is_get_only_without_a_user_session(self):
        class Response(io.BytesIO):
            code = 200

        class Opener:
            def open(inner, req, timeout):
                self.assertEqual(req.method, 'GET')
                self.assertNotIn('Authorization', req.headers)
                self.assertEqual(req.full_url, API + '/auth/v1/health')
                self.assertEqual(timeout, 15)
                return Response(b'{}')

        with patch('qa_public_api_smoke.build_opener', return_value=Opener()):
            self.assertEqual(transport(CONFIG)('/auth/v1/health'), (200, {}))

    def test_malformed_and_oversized_transport_responses_fail(self):
        class Response(io.BytesIO):
            code = 200

        for body in (b'<html>Not JSON</html>', b' ' * (MAX_BODY + 1)):
            with self.subTest(length=len(body)), patch('qa_public_api_smoke.build_opener') as opener:
                opener.return_value.open.return_value = Response(body)
                with self.assertRaises(SmokeFailure):
                    transport(CONFIG)('/auth/v1/health')

    def test_cli_failure_never_prints_exception_or_config_values(self):
        with tempfile.TemporaryDirectory() as tmp:
            cfg = Path(tmp) / 'private.json'
            cfg.write_text(json.dumps(CONFIG))
            output = io.StringIO()
            with patch('sys.argv', ['smoke', '--config', str(cfg)]), \
                    patch('qa_public_api_smoke.run', side_effect=SmokeFailure(CONFIG['anon'])), \
                    contextlib.redirect_stdout(output):
                self.assertEqual(main(), 1)
            self.assertNotIn(CONFIG['anon'], output.getvalue())


if __name__ == '__main__':
    unittest.main()
