import 'package:flutter_test/flutter_test.dart';
import 'package:fleetpilot/auth/password_policy.dart';

void main() {
  test('new registrations require at least 12 characters', () {
    expect(validateAccountPassword('12345678',
        creatingNewPassword: true), 'Use at least 12 characters.');
    expect(validateAccountPassword('12345678901',
        creatingNewPassword: true), 'Use at least 12 characters.');
    expect(validateAccountPassword('123456789012',
        creatingNewPassword: true), isNull);
  });

  test('existing accounts can sign in with legacy 8-character password', () {
    expect(validateAccountPassword('12345678',
        creatingNewPassword: false), isNull);
    expect(validateAccountPassword('1234567',
        creatingNewPassword: false), 'Use at least 8 characters.');
  });

  test('recovery uses the same new-password minimum', () {
    expect(validateAccountPassword('12345678901',
        creatingNewPassword: true), isNotNull);
    expect(validateAccountPassword('123456789012',
        creatingNewPassword: true), isNull);
  });

  test('Polish error messages match requested operation', () {
    expect(validateAccountPassword('short',
        creatingNewPassword: true, locale: 'pl'),
        'Hasło musi mieć co najmniej 12 znaków.');
    expect(validateAccountPassword('short',
        creatingNewPassword: false, locale: 'pl'),
        'Hasło musi mieć co najmniej 8 znaków.');
  });
}
