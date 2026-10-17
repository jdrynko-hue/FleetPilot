import 'dart:convert';

import 'package:fleetpilot/garage/workspace_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const user = '00000000-0000-4000-8000-000000000001';
  var verified = true;
  var writes = 0;
  late Map<String, dynamic> body;
  late SupabaseClient client;
  late MockClient transport;
  setUp(() {
    verified = true; writes = 0;
    transport = MockClient((request) async {
      if (request.url.path == '/auth/v1/token') {
        final expiry = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
        String part(Object value) => base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
        final token = '${part({'alg':'HS256','typ':'JWT'})}.'
          '${part({'sub':user,'role':'authenticated','exp':expiry})}.fixture';
        return http.Response(jsonEncode({
          'access_token': token, 'refresh_token': 'fixture-refresh',
          'token_type':'bearer','expires_in':3600,'expires_at':expiry,
          'user': {'id':user,'aud':'authenticated','role':'authenticated',
            'email':'fixture@example.test','created_at':'2026-10-16T00:00:00Z',
            if (verified) 'email_confirmed_at':'2026-10-16T00:00:00Z',
            'app_metadata':{},'user_metadata':{}},
        }),200,request:request,headers:{'content-type':'application/json'});
      }
      expect(request.url.path, '/rest/v1/garage_workspaces');
      expect(request.method, 'POST');
      writes++;
      body = (jsonDecode(request.body) as Map).cast<String, dynamic>();
      return http.Response(jsonEncode({'id':'00000000-0000-4000-8000-000000000101'}),
        201,request:request,headers:{'content-type':'application/json'});
    });
    client = SupabaseClient('https://fleet-test.invalid','test-anon',httpClient:transport,
      authOptions:const AuthClientOptions(autoRefreshToken:false));
  });
  tearDown(() async { await client.dispose(); transport.close(); });
  Future<void> login() async {
    await client.auth.signInWithPassword(email:'fixture@example.test',password:'fixture-only');
  }
  for (final market in {'GB':'GBP','PL':'PLN','DE':'EUR'}.entries) {
    test('workspace uses current owner and ${market.value} for ${market.key}', () async {
      await login();
      await GarageWorkspaceRepository(client).create(name:'  New Garage  ',country:market.key);
      expect(writes,1);
      expect(body,{'owner_user_id':user,'name':'New Garage','country':market.key,'currency':market.value});
    });
  }
  test('signed-out account cannot insert', () async {
    await expectLater(GarageWorkspaceRepository(client).create(name:'Garage',country:'GB'),throwsStateError);
    expect(writes,0);
  });
  test('unverified email cannot insert from onboarding', () async {
    verified=false; await login();
    await expectLater(GarageWorkspaceRepository(client).create(name:'Garage',country:'GB'),throwsStateError);
    expect(writes,0);
  });
  test('unsupported country and invalid names fail before transport', () async {
    await login();
    for (final invalid in ['', 'A', 'X' * 161]) {
      await expectLater(GarageWorkspaceRepository(client).create(name:invalid,country:'GB'),throwsArgumentError);
    }
    await expectLater(GarageWorkspaceRepository(client).create(name:'Garage',country:'US'),throwsArgumentError);
    expect(writes,0);
  });
}
