// Fail-closed evaluation of the Flotaryx QA catalog-only SQL report.
// Reads locally generated psql output, never contacts a hosted database.
import {readFileSync} from 'node:fs';
const [file,mode='--expect-block']=process.argv.slice(2);
if(!file||!['--expect-block','--release-gate'].includes(mode)){
 console.error('Usage: node qa_catalog_gate.mjs report.txt --expect-block|--release-gate');
 process.exit(2);
}
const expected=Array.from({length:20},(_,i)=>String(i+1).padStart(2,'0'));
const body=readFileSync(file,'utf8');
const records=body.split(/\r?\n/).map(line=>line.trim())
 .filter(s=>/^\d\d_[a-z0-9_]+\|(prerequisite|remediation|independent_review)\|(PASS|HOLD|REVIEW)$/.test(s))
 .map(s=>{const [id,phase,result]=s.split('|');return{id,phase,result}});
const indices=records.map(r=>r.id.slice(0,2));
if(records.length!==20||expected.some((x,i)=>indices[i]!==x)){
 console.error('INVALID REPORT: expected exactly 20 ordered checks, received '+JSON.stringify(indices));
 process.exit(2);
}
if(new Set(records.map(r=>r.id)).size!==20){
 console.error('INVALID REPORT: duplicated check IDs');
 process.exit(2);
}
const checkpoints=new Map(records.map(x=>[x.id,x]));
const mustReview=[
 '15_storage_bucket_and_policy_composition','16_existing_data_fk_integrity',
 '17_active_subscription_write_compatibility',
 '18_authenticated_storage_and_safari_e2e'
];
if(mustReview.some(id=>checkpoints.get(id)?.result!=='REVIEW')){
 // Independent acceptance is intentionally out of scope of catalog-based checks.
 console.error('INVALID REPORT: human acceptance gates are not REVIEW');
 process.exit(2);
}
const counts=Object.fromEntries(['PASS','HOLD','REVIEW'].map(n=>
 [n,records.filter(r=>r.result===n).length]));
const blocked=records.some(r=>r.result!=='PASS');
console.log('QA CATALOG: '+JSON.stringify({checks:records.length,...counts,status:blocked?'DEPLOY_BLOCKED':'CATALOG_CLEAN_ONLY'}));
if(mode==='--release-gate'){
 // Merely passing catalog checks is insufficient for release. Manual approval
 // and independent synthetic + authenticated API tests cannot be waived here.
 console.error('DEPLOY_BLOCKED: catalog data never authorizes deployment.');
 process.exit(3);
}
if(!blocked){console.error('INVALID TEST: expected disposable baseline to be blocked');process.exit(2);}
for(const id of ['02_fleet_documents_rls','03_driver_checks_rls','04_change_requests_rls']){
 if(checkpoints.get(id)?.result!=='HOLD'){
  console.error('UNEXPECTED BASELINE: missing insecure RLS marker '+id);
  process.exit(2);
 }
}
console.log('PASS: known-insecure synthetic QA is blocked and all independent reviews remain required');
