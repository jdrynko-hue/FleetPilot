// Zero-dependency staging-only UI regression for mobile Fleet/Garage demo.
// Use Node's vm to execute the actual embedded JavaScript with a synthetic DOM.
// This intentionally NEVER contacts Supabase, production Fleet, Stripe or APIs.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {Script,createContext} from 'node:vm';

const html=readFileSync(new URL('../web/demo/index.html',import.meta.url),'utf8');
assert.match(html,/<!doctype html>/i);
assert.match(html,/<meta name="robots" content="noindex,nofollow">/);
assert.match(html,/viewport-fit=cover/);
assert.match(html,/@media\(max-width:480px\)/);
assert.match(html,/\[hidden\]\{display:none!important\}/);
assert.match(html,/body:has\(\.view:target\)/);
assert.match(html,/<noscript>/);
assert.doesNotMatch(html,/(?:https?:\/\/|src=['"]\/\/)[^'"\s>]*(?:supabase|stripe|api)/i);
assert.equal((html.match(/<script>/g)||[]).length,2);
for(const role of ['fleet','garage','mechanic','customer']){
 assert.match(html,new RegExp('id="'+role+'"'));
 assert.match(html,new RegExp('href="#'+role+'"'));
 assert.match(html,new RegExp('data-role="'+role+'"'));
}
for(const action of ['send','quote','approve','start','complete','request','confirm'])
 assert.match(html,new RegExp('data-action="'+action+'"'));
assert.ok(html.includes('fictional')||html.includes('fikcyjne'));
assert.match(html,/nie łączą się z bazą produkcyjną/);

const listeners=new Map();
const changedNodes=[];
class TestElement {
 constructor(id='',dataset={}) {
  this.id=id;this.dataset=dataset;this.textContent='';
  this.hidden=false;this.value='';this.attrs={};this.className='';
  this.children=[];this.classList={
   toggle:(key,bool)=>{if(bool)this.className=key;else this.className='';},
   add:(key)=>{this.className=key;},
  };
 }
 addEventListener(event,cb){this.handlers??={};this.handlers[event]=cb}
 setAttribute(k,v){this.attrs[k]=v}
 removeAttribute(k){delete this.attrs[k]}
 replaceChildren(...children){this.children=children}
 scrollIntoView(){this.scrolls=(this.scrolls||0)+1}
 closest(selector){return selector==='[data-action]'?this:null}
}

const ids=new Map();
for(const id of [
 'fleetIssueCount','fleetGarageCount','fleetStatus','garageStatus',
 'mechanicStatus','garageFleetCount','mechanicJobCount','mechanicDone',
 'mechanicStep1','mechanicStep2','garageBookingCount','customerCount',
 'garageBookingStatus','customerStatus','mechanicCustomerStatus','bayStatus',
 'visitDetails','stage1','stage2','stage3','historyList','garageHistory',
 'toast','estimate','service','slot','reset',
 'demoGuide','demoGuideStep','demoGuideProgress','demoGuideTitle',
 'demoGuideHint','demoGuideGo',
 'fleet','garage','mechanic','customer',
])ids.set(id,new TestElement(id));
ids.get('estimate').value='240';
ids.get('service').value='Diagnostyka hamulców';
ids.get('slot').value='2026-11-20T10:00';

const views=['fleet','garage','mechanic','customer'].map(id=>new TestElement(id));
const nav=views.map(v=>new TestElement('',{role:v.id}));
const statuses=[...html.matchAll(/data-show="([^"]+)"/g)].map(v=>new TestElement('',{show:v[1]}));
const booking=[...html.matchAll(/data-booking="([^"]+)"/g)].map(v=>new TestElement('',{booking:v[1]}));
const moneys=[...html.matchAll(/data-money(?:\s|>)/g)].map(()=>new TestElement(''));
const queryList={'.view':views,'[data-role]':nav,'[data-show]':statuses,
 '[data-booking]':booking,'[data-money]':moneys};
const document={
 getElementById:id=>ids.get(id)||null,
 querySelectorAll:q=>queryList[q]||[],
 createElement:tag=>new TestElement(tag),
 addEventListener:(event,cb)=>listeners.set(event,cb),
 documentElement:{classList:{add:()=>{}}},
};
const window={
 location:{hash:'#fleet'},
 addEventListener:(event,cb)=>listeners.set(event,cb),
};
const fakeContext=createContext({
 document,window,console,
 Intl,Number,String,Array,Set,
 setTimeout:()=>1,clearTimeout:()=>{},
});
const scripts=[...html.matchAll(/<script>([\s\S]*?)<\/script>/g)];
for(const script of scripts)new Script(script[1],{filename:'demo-inline.js'}).runInContext(fakeContext);

function tap(action){
 const button=new TestElement('',{action});
 listeners.get('click')({target:button});
}
function switchTo(role){
 window.location.hash='#'+role;
 listeners.get('hashchange')();
 assert.equal(views.filter(v=>v.className==='active').length,1);
 assert.equal(views.find(v=>v.className==='active').id,role);
 assert.equal(nav.find(v=>v.attrs['aria-current']==='page').dataset.role,role);
}
function check(id,text){assert.equal(ids.get(id).textContent,text,id)}
function shown(phase){assert.equal(statuses.some(v=>v.dataset.show.split('|').includes(phase)&&!v.hidden),true)}
function buttonVisible(action,state){
 const el=action==='confirm'||action==='request'
  ?booking.find(b=>b.dataset.booking===state):statuses.find(s=>s.dataset.show===state);
 assert.ok(el&&!el.hidden,action+' should be accessible at '+state);
}

// All 4 role links navigate without reinitializing any scenario state.
for(const role of ['fleet','garage','mechanic','customer'])switchTo(role);
switchTo('fleet');
check('fleetStatus','Nowa usterka');check('fleetGarageCount','0');
check('demoGuideTitle','Zgłoś usterkę we Fleet');
check('demoGuideStep','Krok 1 z 7');
assert.equal(ids.get('demoGuideProgress').value,0);
tap('approve');check('fleetStatus','Nowa usterka'); // no approval without quote
tap('send');check('fleetStatus','Przekazano do Garage');
check('demoGuideTitle','Przygotuj kosztorys w Garage');
assert.equal(ids.get('demoGuideProgress').value,1);
ids.get('demoGuideGo').handlers.click();
assert.equal(window.location.hash,'#garage');
assert.ok(ids.get('garage').scrolls>0);
check('fleetGarageCount','1');switchTo('garage');shown('sent');
ids.get('estimate').value='240';
tap('quote');check('fleetStatus','Kosztorys wysłany');shown('quoted');
check('demoGuideTitle','Zatwierdź kosztorys');
tap('start');check('fleetStatus','Kosztorys wysłany'); // cannot start without approval
switchTo('fleet');tap('approve');check('fleetStatus','Zatwierdzono');
switchTo('mechanic');tap('start');check('fleetStatus','Naprawa trwa');
tap('complete');check('fleetStatus','Naprawa zakończona');
check('demoGuideTitle','Wyślij zapytanie jako klient');
check('fleetIssueCount','0');check('mechanicDone','1');
assert.match(ids.get('historyList').textContent,/240\.00/);
assert.ok(ids.get('garageHistory').children.length>=5);
switchTo('customer');
tap('confirm');check('customerStatus','Nie wysłano'); // no phantom booking
tap('request');check('customerStatus','Oczekuje');
check('demoGuideTitle','Potwierdź wizytę w Garage');
switchTo('garage');tap('confirm');check('garageBookingStatus','Potwierdzona');
switchTo('customer');check('customerStatus','Potwierdzona');
check('demoGuideTitle','Scenariusz ukończony');
check('demoGuideStep','Gotowe');
assert.equal(ids.get('demoGuideProgress').value,7);
check('mechanicJobCount','2'); // two work orders, Fleet and private client
assert.equal(booking.some(v=>v.dataset.booking==='confirmed'&&!v.hidden),true);
listeners.get('hashchange')();
ids.get('reset').handlers.click();
check('fleetStatus','Nowa usterka');
check('fleetIssueCount','1');
check('customerStatus','Nie wysłano');
check('garageBookingStatus','Brak zapytania');
check('demoGuideTitle','Zgłoś usterkę we Fleet');
assert.equal(ids.get('demoGuideProgress').value,0);
assert.equal(ids.get('toast').hidden,false);
console.log('PASS: demo role switching, Fleet quote approvals, repair completion and private booking status sync');
