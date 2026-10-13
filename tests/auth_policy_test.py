import importlib.util
from pathlib import Path
import unittest

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


if __name__ == "__main__":
    unittest.main()
