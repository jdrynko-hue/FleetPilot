"""Atomic fictional-QA path repair; disposable loopback PostgreSQL only."""
from pathlib import Path
import os
import subprocess

ROOT = Path(__file__).resolve().parents[1]
assert os.environ.get('PGHOST') in ('127.0.0.1','localhost'), 'Loopback only'
assert os.environ.get('PGDATABASE') == 'disposable_integrity_review', 'Disposable DB only'
PATCH = ROOT / 'supabase/qa_hardening/data_review/20261015201319_qa_repair_fictional_document_paths.sql'
REPORT = ROOT / 'supabase/qa_hardening/integrity_review/001_boolean_integrity.sql'


def sql(db, query=None, file=None, success=True):
    args=['psql','-X','-A','-t','-v','ON_ERROR_STOP=1','-d',db]
    args+=['-f',str(file)] if file else ['-c',query]
    r=subprocess.run(args,text=True,capture_output=True)
    assert (r.returncode == 0) == success, 'Unexpected SQL outcome'
    return r.stdout if success else r.stderr


snapshot="""SELECT md5(jsonb_agg(to_jsonb(d) ORDER BY id)::text) FROM public.fleet_documents d;
SELECT coalesce(nspacl::text,'') FROM pg_namespace WHERE nspname='public';"""
fixtures=['tests/qa_fleet_auth_bootstrap.sql','supabase/migrations/001_fleetpilot.sql',
 'supabase/migrations/002_saas_foundation.sql','tests/qa_fleet_rls_fixture.sql']
mutation="""UPDATE public.fleet_documents SET storage_path='legacy/fictional.pdf'
 WHERE id='70000000-0000-4000-8000-000000000001';"""
cases=[
 ('success','',''),
 ('storage_bucket',"INSERT INTO storage.buckets VALUES('fiction');",'Storage is not empty'),
 ('storage_object',"INSERT INTO storage.objects VALUES('fiction','legacy/fictional.pdf');",'Storage is not empty'),
 ('unknown_mime',"UPDATE public.fleet_documents SET mime_type='text/plain';",'Unexpected document type'),
 ('foreign_vehicle',"UPDATE public.fleet_documents SET vehicle_id='30000000-0000-4000-8000-000000000003' WHERE id='70000000-0000-4000-8000-000000000001';",'Unexpected document type'),
 ('existing_review','CREATE SCHEMA qa_review_private;','Existing private review schema'),
 # Deliberately reject the UPDATE after backup DDL; the whole transaction
 # must roll back schema, backup and changes. Never disable write triggers.
 ('trigger_rejection',"""CREATE FUNCTION public.reject_path_write() RETURNS trigger
 LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'synthetic write guard'; END $$;
 CREATE TRIGGER reject_path_write BEFORE UPDATE ON public.fleet_documents
 FOR EACH ROW EXECUTE FUNCTION public.reject_path_write();""",'synthetic write guard'),
 ('no_bad_paths',"UPDATE public.fleet_documents SET storage_path=company_id::text||'/'||vehicle_id::text||'/1234567890123456.pdf';",'No invalid fictional'),
]
created=[]
try:
    for name, drift, expected in cases:
        db='disposable_path_'+name
        sql('disposable_integrity_review',f'CREATE DATABASE {db}')
        created.append(db)
        for file in fixtures:
            sql(db,file=ROOT/file)
        sql(db,'CREATE SCHEMA storage; CREATE TABLE storage.buckets(id text); CREATE TABLE storage.objects(bucket_id text,name text);')
        sql(db,mutation)
        if drift:
            sql(db,drift)
        before=sql(db,snapshot)
        schema_before=sql(db,"SELECT to_regnamespace('qa_review_private') IS NOT NULL")
        if expected:
            error=sql(db,file=PATCH,success=False)
            assert expected in error, 'Wrong rejection: '+name
            assert sql(db,snapshot)==before, 'Partial data change: '+name
            assert sql(db,"SELECT to_regnamespace('qa_review_private') IS NOT NULL")==schema_before, 'Partial backup DDL'
            print('PASS:',name,'rejected without partial changes')
        else:
            sql(db,file=PATCH)
            assert sql(db,'SELECT count(*) FROM qa_review_private.document_path_backups').strip()=='1'
            assert sql(db,"SELECT bool_and(original_path='legacy/fictional.pdf') FROM qa_review_private.document_path_backups").strip()=='t'
            assert sql(db,"SELECT bool_and(replacement_path ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/[0-9]{10,20}\\.pdf$') FROM qa_review_private.document_path_backups").strip()=='t'
            assert sql(db,"SELECT count(*) FROM public.fleet_documents WHERE storage_path LIKE '%/safe.pdf'").strip()=='1'
            report=sql(db,file=REPORT)
            rows=[r for r in report.splitlines() if '|' in r]
            assert len(rows)==11 and all(r.endswith('|PASS') for r in rows)
            assert sql(db,"SELECT has_schema_privilege('anon','qa_review_private','USAGE') OR has_schema_privilege('authenticated','qa_review_private','USAGE') OR has_table_privilege('authenticated','qa_review_private.document_path_backups','SELECT')").strip()=='f'
            assert sql(db,"SELECT relrowsecurity FROM pg_class WHERE oid='qa_review_private.document_path_backups'::regclass").strip()=='t'
            # Demonstrate a guarded restoration BEFORE installing path constraints.
            sql(db,"UPDATE public.fleet_documents d SET storage_path=b.original_path FROM qa_review_private.document_path_backups b WHERE d.id=b.document_id AND d.storage_path=b.replacement_path")
            assert sql(db,snapshot)==before, 'Original fictional metadata not recoverable'
            after=sql(db,snapshot)
            sql(db,file=PATCH,success=False)
            assert sql(db,snapshot)==after, 'Replay changed metadata'
            print('PASS: backup private, valid paths untouched, 11 PASS after repair, original path restorable, replay blocked')
finally:
    for db in created:
        sql('disposable_integrity_review',f'DROP DATABASE {db} WITH (FORCE)')
