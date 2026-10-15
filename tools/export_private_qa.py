"""Export the existing single-session UI for an owner-private HTTPS Site.

This validator is configuration validation, not access control. The hosting
provider must enforce owner-only access; the QA database enforces RLS/RPC ACLs.
Only the existing hosted QA is supported. Never supply passwords or JWTs.
"""
import argparse, base64, hashlib, json, re
from pathlib import Path
from urllib.parse import urlsplit

API = 'https://fyestmquqvkdebxxbcky.supabase.co'
FIELDS = {'api', 'anon', 'shop', 'bay', 'company', 'issue', 'mechanicUserId'}
UUID = re.compile(r'^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$', re.I)

def export(origin, cfg, output):
    u = urlsplit(origin)
    if u.scheme != 'https' or not u.hostname or not u.hostname.endswith('.chatgpt.site') or u.netloc != u.hostname or u.path or u.query or u.fragment:
        raise ValueError('Use the exact HTTPS origin returned by owner-private Sites hosting')
    if set(cfg) != FIELDS or cfg['api'] != API or not isinstance(cfg['anon'], str) or not cfg['anon'].startswith('sb_publishable_'):
        raise ValueError('Only a publishable key and the fixed QA API are supported')
    if not all(isinstance(cfg[k], str) and UUID.fullmatch(cfg[k]) for k in FIELDS-{'api','anon'}):
        raise ValueError('Invalid fixture identifier')
    page = (Path(__file__).resolve().parents[1]/'web/demo/session/index.html').read_text()
    validator = '''function valid(){
 if(location.origin!==ORIGIN||!cfg||typeof cfg!=='object')return false;
 const keys=KEYS;
 return Object.keys(cfg).length===keys.length&&keys.every(k=>Object.hasOwn(cfg,k))
  &&cfg.api===API&&typeof cfg.anon==='string'&&cfg.anon.startsWith('sb_publishable_')
  &&['shop','bay','company','issue','mechanicUserId'].every(k=>
   typeof cfg[k]==='string'&&/^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i.test(cfg[k]));
}
'''.replace('ORIGIN',json.dumps(origin)).replace('KEYS',json.dumps(sorted(FIELDS))).replace('API',json.dumps(API))
    start=page.index('function valid(){'); end=page.index('const configured=valid();',start)
    page=page[:start]+validator+page[end:]
    replacements={
      'Flotaryx Single-session QA':'Flotaryx · prywatne QA',
      'Jedno konto na sesję · tylko odizolowany localhost':'Fleet · Garage · rezerwacje',
      '<strong>Środowisko jednorazowe.</strong> Prototyp logowania, wyłącznie dla jednorazowego Supabase i fikcyjnych danych. Nie jest to publiczne środowisko testowe. Bez płatności i kont klientów.':'<strong>Prywatne środowisko testowe.</strong> Rzeczywiste moduły i logowanie, wyłącznie fikcyjne konta i dane. Wersja w rozwoju, bez płatności.',
      'Konfiguracja lokalna nie została zweryfikowana.':'Sprawdzanie konfiguracji środowiska testowego.',
      'Zalogowano do jednorazowego Supabase: ':'Zalogowano do prywatnego QA: ',
      'Flotaryx QA · localhost only · no Stripe Live · no paid providers':'Flotaryx · prywatne QA · dane fikcyjne · bez płatności',
      'Northside Auto Garage — dane testowe':'Flotaryx QA Garage — dane testowe',
      'Mercedes Sprinter · QA-FLEET-001':'Pojazd testowy · QA-FLEET-001',
    }
    for old,new in replacements.items():
        if old not in page: raise ValueError('Source UI changed: review export adapter')
        page=page.replace(old,new)
    scripts=re.findall(r'<script>(.*?)</script>',page,re.S)
    hashes=['\'sha256-'+base64.b64encode(hashlib.sha256(s.encode()).digest()).decode()+"'" for s in scripts]
    csp="default-src 'none'; script-src 'self' "+' '.join(hashes)+"; style-src 'unsafe-inline'; connect-src "+API+"; img-src 'self' data:; base-uri 'none'; form-action 'none'; object-src 'none'"
    page=page.replace('<head>','<head><meta http-equiv="Content-Security-Policy" content="'+csp+'"><meta name="referrer" content="no-referrer">',1)
    output=Path(output);output.mkdir(parents=True,exist_ok=True)
    (output/'index.html').write_text(page)
    (output/'session-config.js').write_text('window.__FLOTARYX_SINGLE_SESSION_QA__='+json.dumps(cfg)+';\n')
    return validator

if __name__=='__main__':
    import sys
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--origin',required=True);p.add_argument('--output',required=True)
    args=p.parse_args();export(args.origin,json.load(sys.stdin),args.output)
    print('PASS: private QA export; no login credentials included')
