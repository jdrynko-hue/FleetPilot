import unittest

from scripts.check_public_password_policy import rejects_short_password


class PublicPasswordPolicyTest(unittest.TestCase):
    def test_actual_length_rejection(self):
        self.assertTrue(rejects_short_password(422, {"weak_password": {"reasons": ["length"]}}))

    def test_other_errors_cannot_pass(self):
        for status, body in [
            (422, {"msg": "Invalid email"}),
            (422, {"weak_password": {"reasons": ["pwned"]}}),
            (429, {"weak_password": {"reasons": ["length"]}}),
            (200, {"weak_password": {"reasons": ["length"]}}),
            (422, None),
        ]:
            with self.subTest(status=status, body=body):
                self.assertFalse(rejects_short_password(status, body))


if __name__ == "__main__":
    unittest.main()
