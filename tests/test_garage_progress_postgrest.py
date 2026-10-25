"""Offline harness checks only: no PostgreSQL/PostgREST/HTTP acceptance claim."""
import base64
import hashlib
import hmac
import json
import os
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch,Mock

from tools import run_garage_progress_postgrest as api

ROOT=Path(__file__).resolve().parents[1]
SCRIPT=ROOT/'tools/run_garage_progress_postgrest_ci.sh'


class ApiHarness(unittest.TestCase):
    def test_locally_issued_signature_and_claims(self):
        key=b'disposable-in-memory-test-key-only'
        value=api.token(key,api.native.OWNER)
        header,payload,signature=value.split('.')
        decode=lambda x:base64.urlsafe_b64decode(x+'='*(-len(x)%4))
        self.assertEqual(json.loads(decode(header)),dict(alg='HS256',typ='JWT'))
        claims=json.loads(decode(payload))
        self.assertEqual(claims['sub'],api.native.OWNER)
        self.assertEqual(claims['role'],'authenticated')
        self.assertGreater(claims['exp'],claims['iat'])
        self.assertEqual(decode(signature),hmac.new(key,(header+'.'+payload).encode(),hashlib.sha256).digest())

    def test_expired_token_is_actually_expired(self):
        with patch.object(api.time,'time',return_value=1000):
            value=api.token(b'test',None,expired=True)
        claims=json.loads(base64.urlsafe_b64decode(value.split('.')[1]+'=='))
        self.assertEqual(claims['exp'],940)
        self.assertNotIn('sub',claims)

    def test_transport_refuses_urls_and_header_override_before_connect(self):
        client=api.Api('/not-used',b'test')
        with patch.object(api,'UnixHttpConnection') as connection:
            for path in ['https://example.test','//example.test/x','/x\r\ny','/x#fragment']:
                with self.assertRaises(ValueError):client.request('GET',path)
            for header in ['Host','Authorization','connection']:
                with self.assertRaises(ValueError):client.request('GET','/x',headers={header:'bad'})
            connection.assert_not_called()

    def test_http_really_uses_unix_socket_not_host_resolution(self):
        with patch.object(api.socket,'socket') as create:
            client=api.UnixHttpConnection('/private/test.sock');client.connect()
            create.assert_called_once_with(api.socket.AF_UNIX,api.socket.SOCK_STREAM)
            create.return_value.connect.assert_called_once_with('/private/test.sock')

    def test_no_auth_header_for_anonymous_and_close_on_invalid_json(self):
        with patch.object(api,'UnixHttpConnection') as create:
            connection=create.return_value
            connection.getresponse.return_value.status=401
            connection.getresponse.return_value.read.return_value=b'{bad'
            with self.assertRaises(json.JSONDecodeError):
                api.Api('/private',b'test').request('GET','/x',auth='none')
            self.assertNotIn('Authorization',connection.request.call_args.kwargs['headers'])
            connection.close.assert_called_once()

    def test_denial_requires_exact_status_code_and_preserved_data(self):
        client=Mock();client.request.return_value=(403,dict(code='42501'))
        run=api.Acceptance(client,object())
        with patch.object(api,'snapshot',return_value={'a':[1]}),patch.object(api,'gate',return_value=False):
            run.error('correct',403,'42501')
            client.request.return_value=(500,dict(code='42501'))
            with self.assertRaises(AssertionError):run.error('wrong-http',403,'42501')
            client.request.return_value=(403,dict(code='40001'))
            with self.assertRaises(AssertionError):run.error('wrong-code',403,'42501')
        self.assertEqual(len(run.records),1)

    def test_denial_rejects_changed_rows_gate_and_foreign_details(self):
        for changed in ['rows','gate','leak']:
            client=Mock();client.request.return_value=(403,dict(code='42501',message=api.SENTINEL if changed=='leak' else 'denied'))
            run=api.Acceptance(client,object())
            with patch.object(api,'snapshot',side_effect=[1,2] if changed=='rows' else None,return_value=1), \
                    patch.object(api,'gate',side_effect=[False,True] if changed=='gate' else None,return_value=False):
                with self.assertRaises(AssertionError):run.error(changed,403,'42501')
            self.assertEqual(run.records,[])

    def test_success_cannot_pass_without_http_audit_readback(self):
        client=Mock();client.request.side_effect=[(200,'ready'),(200,[dict(id=api.ORDER,status='ready')]),(200,[])]
        db=Mock();db.query.return_value=dict(status='ready',start_events=1,events=['mark_ready:'+api.native.OWNER])
        with self.assertRaises(AssertionError):api.Acceptance(client,db).success('missing-audit',api.params())

    def test_export_uses_modern_claims_and_retains_exact_upgrade(self):
        fixture=api.fixture_sql()
        self.assertIn("request.jwt.claims",fixture['before'][0])
        self.assertTrue(fixture['upgrade'].endswith((ROOT/api.native.UPGRADE).read_text()))
        self.assertIn('NOINHERIT NOSUPERUSER',fixture['transport'])
        self.assertNotIn('PASSWORD',fixture['transport'])

    def test_fixture_export_runs_without_database(self):
        result=subprocess.run(['python3','-m','tools.run_garage_progress_postgrest','--export-fixture'],cwd=ROOT,capture_output=True,text=True,timeout=3)
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertEqual(json.loads(result.stdout).keys(),{'before','upgrade','transport'})


class Provisioner(unittest.TestCase):
    def test_all_wrong_environments_refused_before_any_executable(self):
        base=dict(PATH='/not-available',GITHUB_ACTIONS='true',CI='true',RUNNER_ENVIRONMENT='github-hosted',
                  RUNNER_OS='Linux',GITHUB_REPOSITORY='jdrynko-hue/FleetPilot',GARAGE_POSTGREST_DISPOSABLE='1')
        for key,bad in [('GITHUB_ACTIONS',''),('CI','false'),('RUNNER_ENVIRONMENT','self-hosted'),
                        ('RUNNER_OS','Windows'),('GITHUB_REPOSITORY','wrong/repo'),('GARAGE_POSTGREST_DISPOSABLE','0')]:
            with self.subTest(key=key):
                result=subprocess.run(['/bin/bash',str(SCRIPT)],env=dict(base,**{key:bad}),capture_output=True,text=True,timeout=3)
                self.assertEqual(result.returncode,2)
                self.assertIn('REFUSED:',result.stderr)
                self.assertNotIn('command not found',result.stderr)
        result=subprocess.run(['/bin/bash',str(SCRIPT),'--url=https://example.test'],env=base,capture_output=True,text=True,timeout=3)
        self.assertEqual(result.returncode,2)

    def test_shell_and_embedded_python_parse_without_provisioning(self):
        text=SCRIPT.read_text()
        for source in [text,text.split("<<'NATIVE'\n",1)[1].rsplit('\nNATIVE',1)[0]]:
            result=subprocess.run(['/bin/bash','-n'],input=source,text=True,capture_output=True)
            self.assertEqual(result.returncode,0,result.stderr)
        compile(text.split("<<'DOWNLOAD'\n",1)[1].split('\nDOWNLOAD',1)[0],'<download>','exec')
        self.assertIn('5099e7ada38f9f6846cd87c14c5f158b7c165f1e9959665ad412e61f4dceba95',text)
        self.assertIn("members[0].name!='postgrest'",text)


if __name__=='__main__':unittest.main()
