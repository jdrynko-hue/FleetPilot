import importlib.util,json,subprocess,tempfile,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('exporter',ROOT/'tools/export_private_qa.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
class ExportTests(unittest.TestCase):
 def setUp(self):
  self.origin='https://test-owner.chatgpt.site'
  self.cfg=dict(api=m.API,anon='sb_publishable_fixture',**{k:'00000000-0000-4000-8000-000000000001' for k in m.FIELDS-{'api','anon'}})
 def test_reject_configuration(self):
  for patch in [{'api':'https://wqhymmtiawfwjikdaujo.supabase.co'},{'jwt':'secret'},{'password':'secret'},{'shop':'bad'},{'anon':'service_role_key'}]:
   with self.subTest(patch=list(patch)),tempfile.TemporaryDirectory() as out:
    with self.assertRaises(ValueError):m.export(self.origin,self.cfg|patch,out)
 def test_reject_origin(self):
  for origin in ['http://test-owner.chatgpt.site','https://evil.example','https://test-owner.chatgpt.site/path','https://user@test-owner.chatgpt.site','https://test-owner.chatgpt.site:443']:
   with self.subTest(origin=origin),tempfile.TemporaryDirectory() as out:
    with self.assertRaises(ValueError):m.export(origin,self.cfg,out)
 def test_runtime_fail_closed(self):
  with tempfile.TemporaryDirectory() as out:
   validator=m.export(self.origin,self.cfg,out)
   js='const location={origin:'+json.dumps(self.origin)+'};let cfg='+json.dumps(self.cfg)+';'+validator+'''
if(!valid())throw Error('exact config denied');
location.origin='https://other.chatgpt.site';if(valid())throw Error('other origin allowed');
location.origin='''+json.dumps(self.origin)+''';cfg.password='secret';if(valid())throw Error('credentials allowed');
delete cfg.password;cfg.api='https://wqhymmtiawfwjikdaujo.supabase.co';if(valid())throw Error('production allowed');
'''
   subprocess.run(['node','-e',js],check=True)
   page=(Path(out)/'index.html').read_text()
   self.assertIn('Content-Security-Policy',page);self.assertIn("'sha256-",page)
   self.assertIn('noindex,nofollow',page)
   self.assertNotIn('localhost only',page)
   self.assertNotIn('password',json.loads((Path(out)/'session-config.js').read_text().split('=',1)[1].rstrip(';\n')))
if __name__=='__main__':unittest.main()
