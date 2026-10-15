import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fleetpilot/auth/auth_gate.dart';
import 'package:fleetpilot/auth/login_screen.dart';
import 'package:fleetpilot/core/app_config.dart';
import 'package:fleetpilot/ecosystem/ecosystem_gate.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var account=1;
  String userId() => '00000000-0000-4000-8000-00000000000$account';
  setUpAll(() async {
    for(final channel in ['plugins.flutter.io/shared_preferences','com.llfbandit.app_links/events']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MethodChannel(channel),
          (call) async => call.method=='getAll' ? <String,Object>{} : null);
    }
    await Supabase.initialize(url:'https://fyestmquqvkdebxxbcky.supabase.co',
      publishableKey:'sb_publishable_mock_only',
      authOptions:const FlutterAuthClientOptions(autoRefreshToken:false,localStorage:EmptyLocalStorage()),
      httpClient:MockClient((request) async {
        if(request.url.path=='/auth/v1/token') {
          final expiry=DateTime.now().millisecondsSinceEpoch~/1000+3600;
          String part(Object v) => base64Url.encode(utf8.encode(jsonEncode(v))).replaceAll('=','');
          final token='${part({'alg':'HS256','typ':'JWT'})}.${part({'sub':userId(),'role':'authenticated','exp':expiry})}.fixture';
          return http.Response(jsonEncode({'access_token':token,'refresh_token':'mock-refresh',
            'token_type':'bearer','expires_in':3600,'expires_at':expiry,
            'user':{'id':userId(),'aud':'authenticated','role':'authenticated',
              'email':'fixture$account@example.test','created_at':'2026-10-15T00:00:00Z',
              'app_metadata':{},'user_metadata':{'role':'owner'}}}),200,
            headers:{'content-type':'application/json'});
        }
        if(request.url.path=='/auth/v1/logout')return http.Response('{}',200);
        if(request.url.path=='/rest/v1/user_profiles')return http.Response('null',200,headers:{'content-type':'application/json'});
        if(['/rest/v1/company_members','/rest/v1/garage_members'].contains(request.url.path)) {
          return http.Response('[]',200,headers:{'content-type':'application/json'});
        }
        throw StateError('Unexpected mocked request');
      }));
  });
  tearDownAll(() async => Supabase.instance.dispose());
  Future<void> login() => Supabase.instance.client.auth.signInWithPassword(
    email:'fixture$account@example.test',password:'mock-only-password').then((_) {});
  Future<void> openPrivate(WidgetTester tester) async {
    if (AppConfig.ecosystemQaEnabled) {
      await tester.tap(find.byKey(const Key('ecosystem_customer')));
      await tester.pumpAndSettle();
    }
    final context=tester.element(find.byType(AuthGate, skipOffstage:false));
    Navigator.of(context).push<void>(MaterialPageRoute<void>(builder:(_)=>
      const Scaffold(body:Text('Previous account private data'))));
    await tester.pumpAndSettle();
    expect(find.text('Previous account private data'),findsOneWidget);
  }
  testWidgets('logout clears a pushed private route and shows normal login', (tester) async {
    account=1;await tester.runAsync(login);await tester.pumpWidget(const MaterialApp(home:AuthGate()));
    await tester.pumpAndSettle();
    if(AppConfig.ecosystemQaEnabled)expect(find.byType(EcosystemGate),findsOneWidget);
    await openPrivate(tester);
    await tester.runAsync(() => Supabase.instance.client.auth.signOut());await tester.pumpAndSettle();
    expect(find.text('Previous account private data'),findsNothing);
    expect(find.byType(LoginScreen),findsOneWidget);
  }, timeout: const Timeout(Duration(seconds:45)));
  testWidgets('switching accounts cannot leave another account route open', (tester) async {
    account=1;await tester.runAsync(login);await tester.pumpWidget(const MaterialApp(home:AuthGate()));
    await tester.pumpAndSettle();await openPrivate(tester);
    account=2;await tester.runAsync(login);await tester.pumpAndSettle();
    expect(find.text('Previous account private data'),findsNothing);
    expect(find.byType(AuthGate),findsOneWidget);
    if(AppConfig.ecosystemQaEnabled)expect(find.byType(EcosystemGate),findsOneWidget);
  }, timeout: const Timeout(Duration(seconds:45)));
}
