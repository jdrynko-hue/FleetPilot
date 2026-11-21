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


if __name__ == "__main__":
    unittest.main()
