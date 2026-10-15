"""Prove constant-only integrity reports on disposable synthetic PostgreSQL.

No hosted database, URL, key or real customer row is accepted by this runner.
"""
from pathlib import Path
import os
import subprocess

ROOT = Path(__file__).resolve().parents[1]
assert os.environ.get('PGHOST') in ('localhost', '127.0.0.1'), 'Loopback only'
assert os.environ.get('PGDATABASE') == 'disposable_integrity_review', 'Disposable DB only'
REPORT = ROOT / 'supabase/qa_hardening/integrity_review/001_boolean_integrity.sql'


def sql(db, query=None, file=None):
    args = ['psql', '-X', '-A', '-t', '-F', '|', '-v', 'ON_ERROR_STOP=1', '-d', db]
    args += ['-f', str(file)] if file else ['-c', query]
    r = subprocess.run(args, text=True, capture_output=True)
    assert r.returncode == 0, r.stderr
    return r.stdout


A = '20000000-0000-4000-8000-000000000001'
VA1 = '30000000-0000-4000-8000-000000000001'
VA2 = '30000000-0000-4000-8000-000000000002'
VB = '30000000-0000-4000-8000-000000000003'
DB = '40000000-0000-4000-8000-000000000002'
DOC = '70000000-0000-4000-8000-000000000001'
MISSING = 'ffffffff-ffff-4fff-8fff-ffffffffffff'
ids = [
 '01_documents_vehicle', '02_documents_issue', '03_documents_repair',
 '04_checks_vehicle', '05_checks_driver', '06_changes_driver',
 '07_changes_origin', '08_changes_target', '09_document_issue_vehicle',
 '10_document_repair_vehicle', '11_document_storage_prefix',
]

# No application values are printed even in a failing test. Test mutations use
# only published, fictional fixture IDs; they never target a hosted instance.
cases = [
 ('clean', '', set()),
 ('optional_null', 'UPDATE public.driver_vehicle_checks SET driver_id=NULL;', set()),
 ('doc_vehicle', f"UPDATE public.fleet_documents SET vehicle_id='{VB}',storage_path='{A}/{VB}/fiction.pdf' WHERE id='{DOC}';", {'01_documents_vehicle'}),
 ('doc_issue_vehicle', f"UPDATE public.fleet_documents SET issue_id='50000000-0000-4000-8000-000000000002' WHERE id='{DOC}';", {'09_document_issue_vehicle'}),
 ('doc_repair_vehicle', f"UPDATE public.fleet_documents SET repair_id='60000000-0000-4000-8000-000000000002' WHERE id='{DOC}';", {'10_document_repair_vehicle'}),
 ('checks_vehicle', f"UPDATE public.driver_vehicle_checks SET vehicle_id='{VB}';", {'04_checks_vehicle'}),
 ('checks_driver', f"UPDATE public.driver_vehicle_checks SET driver_id='{DB}';", {'05_checks_driver'}),
 ('changes_driver', f"UPDATE public.vehicle_change_requests SET driver_id='{DB}';", {'06_changes_driver'}),
 ('changes_origin', f"UPDATE public.vehicle_change_requests SET from_vehicle_id='{VB}';", {'07_changes_origin'}),
 ('changes_target', f"UPDATE public.vehicle_change_requests SET to_vehicle_id='{VB}';", {'08_changes_target'}),
 ('storage_prefix', f"UPDATE public.fleet_documents SET storage_path='wrong-tenant/fiction.pdf' WHERE id='{DOC}';", {'11_document_storage_prefix'}),
 ('orphan_issue', f"ALTER TABLE public.fleet_documents DROP CONSTRAINT fleet_documents_issue_id_fkey; UPDATE public.fleet_documents SET issue_id='{MISSING}' WHERE id='{DOC}';", {'02_documents_issue'}),
 ('orphan_repair', f"ALTER TABLE public.fleet_documents DROP CONSTRAINT fleet_documents_repair_id_fkey; UPDATE public.fleet_documents SET repair_id='{MISSING}' WHERE id='{DOC}';", {'03_documents_repair'}),
 ('tenant_issue', f"UPDATE public.fleet_documents SET issue_id='50000000-0000-4000-8000-000000000003' WHERE id='{DOC}';", {'02_documents_issue','09_document_issue_vehicle'}),
 ('tenant_repair', f"UPDATE public.fleet_documents SET repair_id='60000000-0000-4000-8000-000000000003' WHERE id='{DOC}';", {'03_documents_repair','10_document_repair_vehicle'}),
]
fixture_files = [
 'tests/qa_fleet_auth_bootstrap.sql', 'supabase/migrations/001_fleetpilot.sql',
 'supabase/migrations/002_saas_foundation.sql', 'tests/qa_fleet_rls_fixture.sql',
]
# Hash only SYNTHETIC local records, not actual hosted data. The hash stays in
# the runner and is never printed; verify the report left application rows intact.
snapshot = "\n".join(
 f"SELECT md5(coalesce(jsonb_agg(to_jsonb(t) ORDER BY id)::text,'')) FROM public.{table} t;"
 for table in ('fleet_documents','driver_vehicle_checks','vehicle_change_requests'))

databases = []
try:
    for name, mutation, expected in cases:
        db = 'disposable_integrity_' + name
        sql('disposable_integrity_review', f'CREATE DATABASE {db}')
        databases.append(db)
        for file in fixture_files:
            sql(db, file=ROOT / file)
        sql(db, """
        INSERT INTO public.issues(id,company_id,vehicle_id,title) VALUES
        ('50000000-0000-4000-8000-000000000003','20000000-0000-4000-8000-000000000002',
         '30000000-0000-4000-8000-000000000003','Fictional B defect');
        INSERT INTO public.repairs(id,company_id,vehicle_id) VALUES
        ('60000000-0000-4000-8000-000000000003','20000000-0000-4000-8000-000000000002',
         '30000000-0000-4000-8000-000000000003');
        """)
        if mutation:
            sql(db, mutation)
        before = sql(db, snapshot)
        output = sql(db, file=REPORT)
        rows = [line.split('|') for line in output.splitlines() if '|' in line]
        assert [r[0] for r in rows] == ids, 'Missing or extra report check'
        assert all(len(r) == 2 and r[1] in ('PASS','HOLD') for r in rows), 'Unexpected report data'
        assert {r[0] for r in rows if r[1] == 'HOLD'} == expected, 'Wrong integrity decision: ' + name
        assert sql(db, snapshot) == before, 'Report modified synthetic data'
        print('PASS:', name, 'constant-only report; synthetic data unchanged')
finally:
    for db in databases:
        sql('disposable_integrity_review', f'DROP DATABASE {db} WITH (FORCE)')
