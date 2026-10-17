import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fleetpilot/core/locale_preferences.dart';
import 'package:fleetpilot/core/localization.dart';
import 'package:fleetpilot/auth/auth_ui_text.dart';
import 'package:fleetpilot/auth/login_screen.dart';
import 'package:fleetpilot/auth/forgot_password_screen.dart';
import 'package:fleetpilot/auth/password_recovery_screen.dart';
import 'package:fleetpilot/auth/portal_entry.dart';

class _MemoryPkceStorage extends GotrueAsyncStorage {
  final _items = <String, String>{};
  @override
  Future<String?> getItem({required String key}) async => _items[key];
  @override
  Future<void> setItem({required String key, required String value}) async {
    _items[key] = value;
  }
  @override
  Future<void> removeItem({required String key}) async { _items.remove(key); }
}

void main() {
  var authRequests = 0;
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('com.llfbandit.app_links/events'), (_) async => null);
    await Supabase.initialize(url: 'https://locale.example.test', publishableKey: 'mock-only',
      authOptions: FlutterAuthClientOptions(autoRefreshToken: false,
        detectSessionInUri: false, localStorage: const EmptyLocalStorage(),
        pkceAsyncStorage: _MemoryPkceStorage()),
      httpClient: MockClient((request) async {
        if (request.url.path == '/auth/v1/signup' || request.url.path == '/auth/v1/token') {
          authRequests++;
        }
        if (request.url.path == '/auth/v1/signup') {
          return http.Response(jsonEncode({'user': {
            'id': '00000000-0000-4000-8000-000000000001',
            'aud': 'authenticated', 'role': 'authenticated',
            'email': 'person@example.test', 'created_at': '2026-01-01T00:00:00Z',
            'app_metadata': {}, 'user_metadata': {'locale': 'pl'},
          }, 'session': null}), 200);
        }
        return http.Response('{"message":"PRIVATE_AUTH_ERROR"}', 400);
      }));
  });
  tearDownAll(() async => Supabase.instance.dispose());
  tearDown(() => initializeAppLanguage(uri: Uri.parse('https://example.test/app/'), device: 'en'));
  for (final register in [false, true]) {
    testWidgets('rapid repeated submit sends one Auth request (register=$register)', (tester) async {
      initializeAppLanguage(uri: Uri.parse('https://example.test/app/?lang=pl'), device: 'en');
      await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
      await tester.pumpAndSettle();
      if (register) {
        final toggle = find.text(tr('no_account'));
        await tester.ensureVisible(toggle);
        await tester.tap(toggle);
        await tester.pumpAndSettle();
      }
      await tester.enterText(find.byType(TextFormField).at(0), 'person@example.test');
      await tester.enterText(find.byType(TextFormField).at(1), 'StrongPassword12!');
      final button = find.byType(FilledButton);
      await tester.ensureVisible(button);
      final before = authRequests;
      // Two taps can reach the old enabled button before the next frame.
      await tester.tap(button);
      await tester.tap(button);
      if (register) {
        for (var frame = 0; frame < 20 && find.text('Sprawdź pocztę').evaluate().isEmpty; frame++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(find.text('Sprawdź pocztę'), findsOneWidget);
        expect(authRequests - before, 1);
        await tester.tap(find.text('OK'));
      }
      await tester.pumpAndSettle();
      expect(authRequests - before, 1);
      expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(authRequests - before, 2);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('Polish login errors are safe and localized', (tester) async {
    initializeAppLanguage(uri: Uri.parse('https://example.test/app/?lang=pl'), device: 'en');
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'person@example.test');
    await tester.enterText(find.byType(TextFormField).at(1), 'StrongPassword12!');
    final button = find.byType(FilledButton);
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('Nie udało się zalogować. Sprawdź dane i spróbuj ponownie.'), findsOneWidget);
    expect(find.textContaining('PRIVATE_AUTH_ERROR'), findsNothing);
  });
  testWidgets('Polish registration confirmation stays Polish without sending real email', (tester) async {
    initializeAppLanguage(uri: Uri.parse('https://example.test/app/?lang=pl'), device: 'en');
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    await tester.pumpAndSettle();
    final register = find.text(tr('no_account'));
    await tester.ensureVisible(register);
    await tester.tap(register);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'person@example.test');
    await tester.enterText(find.byType(TextFormField).at(1), 'StrongPassword12!');
    final button = find.byType(FilledButton);
    await tester.ensureVisible(button);
    await tester.tap(button);
    // Submission stays busy while its confirmation dialog is open.
    for (var frame = 0; frame < 20 && find.text('Sprawdź pocztę').evaluate().isEmpty; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Sprawdź pocztę'), findsOneWidget);
    expect(find.textContaining('Na adres person@example.test wysłaliśmy link'), findsOneWidget);
    expect(find.text('Check your email'), findsNothing);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
  });
  for (final language in supportedLanguages) {
    testWidgets('site $language reaches login, registration and recovery without an English reset', (tester) async {
      initializeAppLanguage(uri: Uri.parse('https://example.test/app/?portal=fleet&lang=$language'), device: 'en');
      tester.view.physicalSize = const Size(390, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
      await tester.pumpAndSettle();
      expect(AppLocale.language.value, language);
      expect(find.text(tr('password')), findsOneWidget);
      final forgot = authText('Forgot password?', 'Nie pamiętasz hasła?');
      expect(find.text(forgot), findsOneWidget);
      if (language == 'pl') {
        expect(find.text('Hasło'), findsOneWidget);
        expect(find.text('Password'), findsNothing);
        expect(find.text('Forgot password?'), findsNothing);
      }
      final register = find.text(tr('no_account'));
      await tester.ensureVisible(register);
      await tester.tap(register);
      await tester.pumpAndSettle();
      expect(find.text(tr('create_account')), findsWidgets);
      await tester.pumpWidget(MaterialApp(home: ForgotPasswordScreen(requestReset: (_) async {})));
      await tester.pumpAndSettle();
      expect(find.text(authText('Password recovery', 'Odzyskiwanie hasła')), findsOneWidget);
      expect(find.text(authText('Send reset link', 'Wyślij link do zmiany hasła')), findsOneWidget);
      await tester.pumpWidget(MaterialApp(home: PasswordRecoveryScreen(updatePassword: (_) async {})));
      await tester.pumpAndSettle();
      expect(find.text(authText('New password', 'Nowe hasło')), findsOneWidget);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: PortalEntryPicker(
        selected: PortalEntry.fleet, onSelected: (_) {}, onFindWorkshop: () {}))));
      await tester.pumpAndSettle();
      if (language == 'pl') {
        expect(find.text('Choose a module'), findsNothing);
        expect(find.text('My bookings'), findsNothing);
        expect(find.text('Find a workshop'), findsNothing);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
