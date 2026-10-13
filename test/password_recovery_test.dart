import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fleetpilot/auth/forgot_password_screen.dart';
import 'package:fleetpilot/auth/password_recovery_screen.dart';
import 'package:fleetpilot/core/localization.dart';

void main() {
  testWidgets('invalid recovery email does not send a request', (tester) async {
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
      home: ForgotPasswordScreen(requestReset: (email) async { calls++; }),
    ));
    await tester.enterText(find.byKey(const Key('reset_email')), 'not-an-email');
    await tester.tap(find.byKey(const Key('request_reset_button')));
    await tester.pumpAndSettle();
    expect(find.text('Enter a valid email address.'), findsOneWidget);
    expect(calls, 0);
  });

  testWidgets('recovery request shows generic account-neutral confirmation',
      (tester) async {
    String? email;
    await tester.pumpWidget(MaterialApp(
      home: ForgotPasswordScreen(
        requestReset: (value) async { email = value; },
      ),
    ));
    await tester.enterText(
      find.byKey(const Key('reset_email')),
      ' person@example.com ',
    );
    await tester.tap(find.byKey(const Key('request_reset_button')));
    await tester.pumpAndSettle();
    expect(email, 'person@example.com');
    expect(find.byKey(const Key('reset_request_confirmation')), findsOneWidget);
    expect(find.textContaining('If an account exists'), findsOneWidget);
  });

  testWidgets('Polish-language recovery form is localized', (tester) async {
    AppLocale.language.value = 'pl';
    addTearDown(() => AppLocale.language.value = 'en');
    await tester.pumpWidget(MaterialApp(
      home: ForgotPasswordScreen(requestReset: (email) async {}),
    ));
    expect(find.text('Odzyskiwanie hasła'), findsOneWidget);
    expect(find.text('Wyślij link do zmiany hasła'), findsOneWidget);
  });

  testWidgets('short password never updates the account', (tester) async {
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
      home: PasswordRecoveryScreen(updatePassword: (password) async { calls++; }),
    ));
    await tester.enterText(find.byKey(const Key('new_password')), 'short');
    await tester.enterText(find.byKey(const Key('confirm_password')), 'short');
    await tester.tap(find.byKey(const Key('set_password_button')));
    await tester.pumpAndSettle();
    expect(find.text('Use at least 12 characters.'), findsOneWidget);
    expect(calls, 0);
  });

  testWidgets('mismatching confirmation never updates password', (tester) async {
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
      home: PasswordRecoveryScreen(updatePassword: (password) async { calls++; }),
    ));
    await tester.enterText(
      find.byKey(const Key('new_password')), 'LongStrongPassword1!',
    );
    await tester.enterText(
      find.byKey(const Key('confirm_password')), 'DifferentStrongPassword1!',
    );
    await tester.tap(find.byKey(const Key('set_password_button')));
    await tester.pumpAndSettle();
    expect(find.text('Passwords do not match.'), findsOneWidget);
    expect(calls, 0);
  });

  testWidgets('valid password is updated and signs user out', (tester) async {
    String? savedPassword;
    var signOuts = 0;
    await tester.pumpWidget(MaterialApp(
      home: PasswordRecoveryScreen(
        updatePassword: (password) async { savedPassword = password; },
        onCompleted: () async { signOuts++; },
      ),
    ));
    await tester.enterText(
      find.byKey(const Key('new_password')), 'LongStrongPassword1!',
    );
    await tester.enterText(
      find.byKey(const Key('confirm_password')), 'LongStrongPassword1!',
    );
    await tester.tap(find.byKey(const Key('set_password_button')));
    await tester.pumpAndSettle();
    expect(savedPassword, 'LongStrongPassword1!');
    expect(signOuts, 1);
    expect(find.byKey(const Key('password_recovery_completed')), findsOneWidget);
  });

  testWidgets('password update failure does not report success', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: PasswordRecoveryScreen(
        updatePassword: (password) async => throw StateError('expired'),
      ),
    ));
    await tester.enterText(
      find.byKey(const Key('new_password')), 'LongStrongPassword1!',
    );
    await tester.enterText(
      find.byKey(const Key('confirm_password')), 'LongStrongPassword1!',
    );
    await tester.tap(find.byKey(const Key('set_password_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('password_recovery_error')), findsOneWidget);
    expect(find.byKey(const Key('password_recovery_completed')), findsNothing);
  });
}
