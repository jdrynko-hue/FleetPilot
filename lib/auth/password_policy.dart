import 'auth_ui_text.dart';

/// Client-side password guidance. Supabase Auth settings enforce the actual
/// minimum and compromised-password policy on the server.
const int minimumNewPasswordLength = 12;
const int minimumExistingLoginPasswordLength = 8;

/// New accounts and password recovery use 12 characters. Existing accounts
/// can still sign in with their original password (at least 8 characters).
String? validateAccountPassword(
  String? value, {
  required bool creatingNewPassword,
  String locale = 'en',
}) {
  final password = value ?? '';
  final minimum = creatingNewPassword
      ? minimumNewPasswordLength
      : minimumExistingLoginPasswordLength;
  if (password.length >= minimum) return null;
  if (creatingNewPassword) {
    return authText('Use at least 12 characters.',
      'Hasło musi mieć co najmniej 12 znaków.', language: locale);
  }
  return authText('Use at least 8 characters.',
    'Hasło musi mieć co najmniej 8 znaków.', language: locale);
}
