import importlib.util
import io
import json
from contextlib import redirect_stdout
from pathlib import Path
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("auth_policy", Path(__file__).parents[1] / "scripts/verify_auth_policy.py")
auth_policy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(auth_policy)


class AuthPolicyTests(unittest.TestCase):
    def test_raise_weak_minimum_without_changing_other_settings(self):
        config = {"password_min_length": 6, "uri_allow_list": auth_policy.APP_REDIRECT,
                  "mailer_autoconfirm": False, "smtp_pass": "fake secret"}
        original = dict(config)
        self.assertEqual(auth_policy.policy_patch(config), {"password_min_length": 12})
        self.assertEqual(config, original)

    def test_preserve_stronger_password_policy(self):
        self.assertEqual(auth_policy.policy_patch({"password_min_length": 16, "uri_allow_list": auth_policy.APP_REDIRECT}), {})

    def test_append_exact_redirect_without_removing_existing_entries(self):
        original = "https://flotaryx.com/,https://flotaryx.com/app/**"
        self.assertEqual(auth_policy.policy_patch({"password_min_length": 12, "uri_allow_list": original}),
                         {"uri_allow_list": original + "," + auth_policy.APP_REDIRECT})

    def test_reject_unexpected_configuration_without_mutation(self):
        for minimum in [None, False, "12", 0]:
            with self.assertRaises(ValueError):
                auth_policy.policy_patch({"password_min_length": minimum})
        with self.assertRaises(ValueError):
            auth_policy.policy_patch({"password_min_length": 12, "uri_allow_list": []})


    def test_default_release_verification_does_not_patch_a_mismatch(self):
        current = {"password_min_length": 6, "uri_allow_list": ""}
        with patch.dict("os.environ", {"SUPABASE_ACCESS_TOKEN": "fixture"}):
            with patch.object(auth_policy.urllib.request, "urlopen") as urlopen:
                urlopen.return_value = io.StringIO(json.dumps(current))
                with self.assertRaisesRegex(SystemExit, "password_min_length, uri_allow_list"):
                    auth_policy.main([])
        self.assertEqual([call.args[0].get_method() for call in urlopen.call_args_list], ["GET"])

    def test_opt_in_applies_and_verifies_only_required_fields(self):
        current = {"password_min_length": 6, "uri_allow_list": auth_policy.APP_REDIRECT}
        updated = {**current, "password_min_length": 12}
        with patch.dict("os.environ", {"SUPABASE_ACCESS_TOKEN": "fixture"}):
            with patch.object(auth_policy.urllib.request, "urlopen") as urlopen:
                urlopen.side_effect = [io.StringIO(json.dumps(current)),
                                       io.StringIO("{}"),
                                       io.StringIO(json.dumps(updated))]
                with redirect_stdout(io.StringIO()):
                    auth_policy.main(["--apply"])
        requests = [call.args[0] for call in urlopen.call_args_list]
        self.assertEqual([request.get_method() for request in requests], ["GET", "PATCH", "GET"])
        self.assertEqual(json.loads(requests[1].data), {"password_min_length": 12})


class QaAuthPolicyTests(unittest.TestCase):
    callback = "https://reviewed-qa.example.chatgpt.site/app/"

    def test_qa_requires_base_and_each_supported_portal(self):
        expected = auth_policy.qa_redirects(self.callback)
        self.assertEqual(len(expected), 5)
        for omitted in expected:
            config = {"password_min_length": 12, "uri_allow_list": ",".join(v for v in expected if v != omitted)}
            self.assertIn(omitted, auth_policy.policy_patch(config, expected)["uri_allow_list"])

    def test_wildcard_does_not_replace_exact_entries(self):
        expected = auth_policy.qa_redirects(self.callback)
        config = {"password_min_length": 12, "uri_allow_list": "https://**.chatgpt.site/**"}
        self.assertIn("uri_allow_list", auth_policy.policy_patch(config, expected))

    def test_invalid_callback_rejected(self):
        for url in ["", "http://qa.chatgpt.site/app/", "https://flotaryx.com/app/",
                    "https://qa.chatgpt.site.evil.test/app/", "https://user@qa.chatgpt.site/app/",
                    "https://qa.chatgpt.site:443/app/", "https://*.chatgpt.site/app/",
                    self.callback + "?portal=garage", self.callback + "#secret",
                    self.callback + "?", "https://qa.chatgpt.site/", "https://qa.chatgpt.site/app/ "]:
            with self.subTest(url=url), self.assertRaises(ValueError):
                auth_policy.qa_redirects(url)

    def test_qa_success_reads_only_qa_project_and_redacts_config(self):
        config = {"password_min_length": 12, "uri_allow_list": ",".join(auth_policy.qa_redirects(self.callback)), "smtp_pass": "hidden-fixture"}
        output = io.StringIO()
        with patch.dict("os.environ", {"SUPABASE_ACCESS_TOKEN": "fixture"}), patch.object(auth_policy.urllib.request, "urlopen") as request:
            request.return_value = io.StringIO(json.dumps(config))
            with redirect_stdout(output):
                auth_policy.main(["--environment", "qa", "--qa-callback", self.callback])
        self.assertEqual(request.call_count, 1)
        self.assertEqual(request.call_args.args[0].get_method(), "GET")
        self.assertIn(auth_policy.QA_PROJECT_REF, request.call_args.args[0].full_url)
        self.assertNotIn("hidden-fixture", output.getvalue())
        self.assertNotIn(self.callback, output.getvalue())

    def test_qa_mismatch_never_patches(self):
        with patch.dict("os.environ", {"SUPABASE_ACCESS_TOKEN": "fixture"}), patch.object(auth_policy.urllib.request, "urlopen") as request:
            request.return_value = io.StringIO('{"password_min_length":6,"uri_allow_list":""}')
            with self.assertRaisesRegex(SystemExit, "password_min_length, uri_allow_list"):
                auth_policy.main(["--environment", "qa", "--qa-callback", self.callback])
        self.assertEqual([c.args[0].get_method() for c in request.call_args_list], ["GET"])

    def test_invalid_mode_options_fail_before_network(self):
        from contextlib import redirect_stderr
        with patch.object(auth_policy.urllib.request, "urlopen") as request, redirect_stderr(io.StringIO()):
            for args in [["--environment", "qa", "--apply"], ["--environment", "qa"], ["--qa-callback", self.callback]]:
                with self.assertRaises(SystemExit):
                    auth_policy.main(args)
            request.assert_not_called()


if __name__ == "__main__":
    unittest.main()
