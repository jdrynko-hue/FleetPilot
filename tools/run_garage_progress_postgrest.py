"""Disposable native PostgREST HTTP/JWT acceptance, never hosted Auth E2E.

Only a fresh, marked private PG17 cluster is accepted. HTTP uses a Unix socket,
not a URL/DSN. All identities and the in-memory signing key belong to this run.
No hosted key, browser session or real account is read, created or changed.
"""
import argparse
import base64
import hashlib
import hmac
import http.client
import json
import os
from pathlib import Path
import secrets
import socket
import subprocess
import time
from urllib.parse import urlencode

from tools import run_garage_progress_concurrency as native

ROOT = Path(__file__).resolve().parents[1]
RPC = '/rpc/garage_advance_ordinary_order'
POSTGREST_VERSION = '16.5'
AUTHENTICATOR = 'fixture_authenticator'
OTHER_SHOP = native.ident(102)
ORDER = native.ident(421)
SENTINEL = 'FOREIGN-PRIVATE-HTTP-FIXTURE'


def claims_uid_fixture():
    # Match Supabase's modern claims + legacy sub lookup; no production override.
    return native.AUTH_FIXTURE.replace(
        "nullif(current_setting('request.jwt.claim.sub',true),'')::uuid",
        "coalesce(nullif(current_setting('request.jwt.claim.sub',true),''),"
        "nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'sub')::uuid")


def fixture_sql():
    seeds = [native.seed(dict(order=native.ident(n), initial='in_progress'))
             for n in range(421, 427)]
    extra = f"""
SELECT set_config('request.jwt.claim.sub','{native.ident(2)}',false);
INSERT INTO public.garage_workspaces(id,owner_user_id,name,country,currency)
VALUES('{OTHER_SHOP}','{native.ident(2)}','{SENTINEL}','GB','GBP');
INSERT INTO public.garage_members(workspace_id,user_id,role)
VALUES('{OTHER_SHOP}','{native.ident(5)}','mechanic');
INSERT INTO public.garage_customers(id,workspace_id,customer_type,display_name)
VALUES('{native.ident(202)}','{OTHER_SHOP}','individual','{SENTINEL}');
INSERT INTO public.garage_vehicles(id,workspace_id,customer_id,make,model)
VALUES('{native.ident(302)}','{OTHER_SHOP}','{native.ident(202)}','QA','Private');
INSERT INTO public.garage_work_orders(id,workspace_id,vehicle_id,assigned_user_id,created_by,complaint,status)
VALUES('{native.ident(431)}','{OTHER_SHOP}','{native.ident(302)}','{native.ident(5)}',
 '{native.ident(2)}','{SENTINEL}','in_progress');
UPDATE public.garage_work_orders SET assigned_user_id=NULL WHERE id='{native.ident(422)}';
INSERT INTO public.garage_quote_revisions(workspace_id,order_id,revision,currency,
 subtotal_minor,tax_minor,total_minor,published_by)
VALUES('{native.SHOP}','{native.ident(423)}',2,'GBP',200,0,200,'{native.OWNER}');
INSERT INTO public.companies(id,name) VALUES('{native.ident(601)}','Synthetic Fleet');
INSERT INTO public.vehicles(id,company_id,registration)
VALUES('{native.ident(602)}','{native.ident(601)}','SYNTHETIC');
INSERT INTO public.issues(id,company_id,vehicle_id,title)
VALUES('{native.ident(603)}','{native.ident(601)}','{native.ident(602)}','Synthetic issue');
INSERT INTO public.garage_fleet_connections(company_id,workspace_id,status,requested_by)
VALUES('{native.ident(601)}','{native.SHOP}','active','{native.OWNER}');
INSERT INTO public.garage_fleet_requests(company_id,workspace_id,issue_id,fleet_vehicle_id,
 garage_order_id,status,issue_title,sent_by)
VALUES('{native.ident(601)}','{native.SHOP}','{native.ident(603)}','{native.ident(602)}',
 '{native.ident(424)}','accepted','Synthetic issue','{native.OWNER}');
"""
    transport = f"""CREATE ROLE {AUTHENTICATOR} LOGIN NOINHERIT NOSUPERUSER
 NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
GRANT anon,authenticated TO {AUTHENTICATOR};
"""
    return dict(before=[claims_uid_fixture()] + [(ROOT/p).read_text() for p in native.BASES]
                + [native.ACTORS_FIXTURE] + seeds + [extra],
                upgrade="SET flotaryx.ordinary_progress_local_review='approved-local-fixture';\n"
                + (ROOT/native.UPGRADE).read_text(), transport=transport)


def snapshot(db):
    # Keep full values, not just counts, for detecting accidental state changes.
    return db.query("""SELECT json_build_object(
      'orders',(SELECT json_agg(x ORDER BY id) FROM public.garage_work_orders x),
      'quotes',(SELECT json_agg(x ORDER BY id) FROM public.garage_quote_revisions x),
      'approvals',(SELECT json_agg(x ORDER BY id) FROM public.garage_quote_approvals x),
      'events',(SELECT json_agg(x ORDER BY id) FROM public.garage_order_events x),
      'requests',(SELECT json_agg(x ORDER BY id) FROM public.garage_fleet_requests x),
      'members',(SELECT json_agg(x ORDER BY workspace_id,user_id) FROM public.garage_members x),
      'policies',(SELECT json_agg(x ORDER BY schemaname,tablename,policyname) FROM pg_policies x));""")


def gate(db):
    return db.query("SELECT json_build_object('rows',count(*),'closed',bool_and(singleton AND NOT enabled)) FROM garage_private.ordinary_progress_control;")


def prepare(db):
    script = fixture_sql()
    for sql in script['before']:
        db.run(sql)
    before = snapshot(db)
    db.run(script['upgrade'])
    if snapshot(db) != before or gate(db) != dict(rows=1, closed=True):
        raise AssertionError('Populated upgrade/default closed gate failed')
    db.run(script['transport'])


def encode64(value):
    return base64.urlsafe_b64encode(value).decode().rstrip('=')


def token(key, actor, *, role='authenticated', expired=False, metadata=None):
    now = int(time.time())
    claims = dict(role=role, iat=now-120 if expired else now,
                  exp=now-60 if expired else now+600)
    if actor is not None:
        claims['sub'] = actor
    if metadata is not None:
        claims['user_metadata'] = metadata
    data = '.'.join(encode64(json.dumps(x, separators=(',', ':')).encode())
                    for x in [dict(alg='HS256', typ='JWT'), claims])
    return data + '.' + encode64(hmac.new(key, data.encode(), hashlib.sha256).digest())


class UnixHttpConnection(http.client.HTTPConnection):
    def __init__(self, path):
        super().__init__('localhost', timeout=5)
        self.path = path

    def connect(self):
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.settimeout(self.timeout)
        self.sock.connect(str(self.path))


class Api:
    def __init__(self, path, key):
        self.path, self.key = path, key

    def request(self, method, path, actor=native.OWNER, payload=None,
                *, auth='valid', role='authenticated', metadata=None, headers=None):
        if not path.startswith('/') or path.startswith('//') or any(c in path for c in '\r\n#'):
            raise ValueError('Only relative API paths on the private Unix socket')
        if headers and any(k.lower() in ('authorization','host','connection') for k in headers):
            raise ValueError('Transport/auth headers may not be overridden')
        h = {'Accept': 'application/json', 'Connection': 'close'}
        if auth != 'none':
            key = b'wrong-synthetic-signature-key-only' if auth == 'wrong_signature' else self.key
            h['Authorization'] = 'Bearer ' + token(key, actor, role=role,
                expired=auth == 'expired', metadata=metadata)
        if headers:
            h.update(headers)
        body = None if payload is None else json.dumps(payload)
        if body is not None:
            h['Content-Type'] = 'application/json'
        connection = UnixHttpConnection(self.path)
        try:
            connection.request(method, path, body=body, headers=h)
            response = connection.getresponse()
            content = response.read(1024*1024+1)
            if len(content) > 1024*1024:
                raise AssertionError('Unbounded API response')
            return response.status, None if not content else json.loads(content)
        finally:
            connection.close()


def params(order=ORDER, workspace=native.SHOP, source='in_progress', target='ready'):
    return dict(p_workspace_id=workspace, p_order_id=order,
                p_from_status=source, p_target_status=target)


class Acceptance:
    def __init__(self, api, db):
        self.api, self.db, self.records = api, db, []

    def error(self, name, status, code, *, method='POST', path=RPC,
              actor=native.OWNER, payload=None, **kwargs):
        before, closed = snapshot(self.db), gate(self.db)
        actual, result = self.api.request(method, path, actor,
            params() if payload is None and method == 'POST' else payload, **kwargs)
        if actual != status or not isinstance(result, dict) or result.get('code') != code:
            raise AssertionError(f'{name}: expected HTTP {status}/{code}; got HTTP {actual}/{result.get("code") if isinstance(result,dict) else "non-error"}')
        if SENTINEL in json.dumps(result) or snapshot(self.db) != before or gate(self.db) != closed:
            raise AssertionError(name + ': denial leaked foreign details or changed durable state')
        self.records.append(dict(case=name, http_status=actual, code=code, unchanged=True))

    def success(self, name, payload, actor=native.OWNER):
        status, body = self.api.request('POST', RPC, actor, payload)
        if status != 200 or body != payload['p_target_status']:
            raise AssertionError(f'{name}: expected exact scalar status response')
        order = payload['p_order_id']
        state = self.db.query(native.state_sql(order))
        expected = payload['p_target_status']
        if state['status'] != expected or state['start_events'] != 1:
            raise AssertionError(name + ': persisted state/start event disagrees')
        events = ['mark_ready:'+native.OWNER]
        if expected == 'collected':
            events.append('confirm_collection:'+native.ADVISER)
        if sorted(state['events']) != sorted(events):
            raise AssertionError(name + ': duplicate/misattributed audit')
        # Both business state and event actor must also be visible via normal HTTP reads.
        read_status, rows = self.api.request('GET', '/garage_work_orders?'+urlencode(
            dict(id='eq.'+order, select='id,status')), native.OWNER)
        event_status, audits = self.api.request('GET', '/garage_order_events?'+urlencode(
            dict(order_id='eq.'+order, select='action,actor_user_id')), native.OWNER)
        wanted = sorted(events + ['start_approved_repair:'+native.OWNER])
        if read_status != 200 or rows != [dict(id=order,status=expected)] or event_status != 200 \
                or sorted(x['action']+':'+x['actor_user_id'] for x in audits) != wanted:
            raise AssertionError(name + ': normal HTTP read/audit disagrees')
        self.records.append(dict(case=name, http_status=status, persisted_status=expected,
                                 event_count=len(events), http_readback=True))

    def hidden(self, name, actor, query):
        before = snapshot(self.db)
        status, rows = self.api.request('GET', '/garage_work_orders?'+urlencode(
            dict(query,select='id,status,complaint')),actor)
        if status != 200 or rows != [] or snapshot(self.db) != before:
            raise AssertionError(name + ': row visibility leak')
        self.records.append(dict(case=name,http_status=status,visible_rows=0))

    def run(self):
        self.error('owner_default_closed',403,'42501')
        self.db.run('UPDATE garage_private.ordinary_progress_control SET enabled=true;')
        self.error('anonymous',401,'42501',auth='none')
        for name,actor in [('foreign_owner',2),('mechanic',3),('foreign_mechanic',5),
                           ('customer',6),('unrelated',8)]:
            self.error(name,403,'42501',actor=native.ident(actor))
        self.error('missing_subject',403,'42501',actor=None)
        self.error('wrong_signature',401,'PGRST301',auth='wrong_signature')
        self.error('expired',401,'PGRST303',auth='expired')
        self.error('metadata_is_not_authority',403,'42501',actor=native.MECHANIC,
                   metadata=dict(role='owner',workspace_id=native.SHOP))
        self.error('capability_header_is_not_authority',403,'42501',actor=native.MECHANIC,
                   headers={'X-Client-Info':'flotaryx-maintenance/2'})
        self.error('cannot_set_superuser_role',403,'42501',role='postgres')
        self.error('workspace_mismatch',403,'42501',payload=params(workspace=OTHER_SHOP))
        self.error('foreign_order_uuid',403,'42501',payload=params(order=native.ident(431)))
        self.error('missing_order',403,'42501',payload=params(order=native.ident(999)))
        self.error('no_mechanic',403,'42501',payload=params(order=native.ident(422)))
        self.error('new_unapproved_revision',403,'42501',payload=params(order=native.ident(423)))
        self.error('fleet_link_cannot_bypass',403,'42501',payload=params(order=native.ident(424)))
        self.error('invalid_transition',400,'22023',payload=params(target='collected'))
        self.error('get_cannot_write',405,'25006',method='GET',path=RPC+'?'+urlencode(params()))
        self.error('missing_argument',404,'PGRST202',payload={k:v for k,v in params().items() if k!='p_target_status'})
        self.error('extra_argument',404,'PGRST202',payload=dict(params(), unexpected=True))
        self.error('wrong_uuid_type',400,'22P02',payload=params(order='not-a-uuid'))
        self.error('direct_order_update',403,'42501',method='PATCH',path='/garage_work_orders?'+urlencode(dict(id='eq.'+ORDER)),payload=dict(status='collected'))
        self.error('private_control_not_public',404,'PGRST205',method='GET',path='/ordinary_progress_control')
        self.error('private_schema_not_exposed',406,'PGRST106',method='GET',path='/ordinary_progress_control',headers={'Accept-Profile':'garage_private'})
        self.hidden('owner_foreign_row_hidden',native.OWNER,dict(workspace_id='eq.'+OTHER_SHOP))
        self.hidden('foreign_owner_our_row_hidden',native.ident(2),dict(id='eq.'+ORDER))
        self.hidden('customer_row_hidden',native.ident(6),dict(id='eq.'+ORDER))
        self.hidden('mechanic_unassigned_hidden',native.MECHANIC,dict(id='eq.'+native.ident(422)))
        self.success('owner_ready',params())
        self.success('ready_replay',params())
        self.success('adviser_collection',params(source='ready',target='collected'),native.ADVISER)
        self.success('collection_replay',params(source='ready',target='collected'),native.ADVISER)
        # Raw PostgreSQL 40001 maps to HTTP500 in PostgREST16, not HTTP409.
        self.error('stale_ready_after_collection',500,'40001')
        self.success('second_owner_ready',params(order=native.ident(425)))
        self.db.run(f"UPDATE public.garage_work_orders SET assigned_user_id=NULL WHERE id='{native.ident(425)}';")
        self.success('unassigned_ready_collection',params(order=native.ident(425),source='ready',target='collected'),native.ADVISER)
        self.db.run('UPDATE garage_private.ordinary_progress_control SET enabled=false;')
        self.error('reclosed_gate',403,'42501',payload=params(order=native.ident(426)))
        for record in self.records:
            print(json.dumps(record,sort_keys=True),flush=True)
        print(f'PASS {len(self.records)} actual PostgREST HTTP/JWT fixture cases; NOT hosted Auth/browser E2E',flush=True)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--socket-dir')
    parser.add_argument('--port',type=int,default=55432)
    parser.add_argument('--approve-disposable-cluster',action='store_true')
    parser.add_argument('--export-fixture',action='store_true')
    args=parser.parse_args()
    if args.export_fixture:
        print(json.dumps(fixture_sql()))
        return
    if not args.socket_dir or os.getuid()==0:
        raise ValueError('Private marked socket and existing nonroot OS user required')
    directory=native.local_socket(args.socket_dir,args.port,args.approve_disposable_cluster)
    db=native.Database(directory,args.port,'postgres')
    native.require_fresh_database(db)  # SELECT-only guard precedes all mutations/processes.
    version=subprocess.run(['postgrest','--version'],capture_output=True,text=True,check=True,timeout=5).stdout.strip()
    if version != 'PostgREST '+POSTGREST_VERSION:
        raise ValueError('Exact reviewed PostgREST version required')
    prepare(db)
    key=secrets.token_urlsafe(48).encode()  # Disposable signing key, never printed or persisted.
    path=directory/'postgrest.sock'
    env=dict(PATH=os.environ['PATH'],LANG='C.UTF-8',PGRST_DB_URI=
        f'host={directory} port={args.port} dbname={native.DATABASE} user={AUTHENTICATOR}',
        PGRST_DB_ANON_ROLE='anon',PGRST_DB_SCHEMAS='public',PGRST_DB_CONFIG='false',
        PGRST_DB_CHANNEL_ENABLED='false',PGRST_DB_POOL='2',PGRST_JWT_SECRET=key.decode(),
        PGRST_SERVER_UNIX_SOCKET=str(path),PGRST_SERVER_UNIX_SOCKET_MODE='600',PGRST_LOG_LEVEL='crit')
    process=subprocess.Popen(['postgrest'],env=env,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    api=Api(path,key)
    try:
        deadline=time.monotonic()+20
        while True:
            if process.poll() is not None:
                raise RuntimeError('PostgREST exited before acceptance; no credential output')
            try:
                status,body=api.request('GET','/garage_work_orders?select=id&limit=1')
                if status==200 and isinstance(body,list) and len(body)==1:
                    break
            except OSError:
                pass
            if time.monotonic()>deadline:
                raise TimeoutError('PostgREST readiness not achieved')
            time.sleep(.1)
        files=native.BASES+[native.UPGRADE,'tools/run_garage_progress_postgrest.py']
        print(json.dumps(dict(engine=db.query('SELECT to_json(version());'),postgrest=version,
            source_sha256={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in files},
            transport='HTTP over private Unix socket; locally issued verified JWTs',
            hosted_auth=False)),flush=True)
        Acceptance(api,db).run()
    finally:
        process.terminate()
        try:
            process.wait(timeout=8)
        except subprocess.TimeoutExpired:
            process.kill();process.wait(timeout=3)


if __name__=='__main__':
    main()
