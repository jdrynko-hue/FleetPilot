import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
// Executes the actual inline language script with a minimal DOM fixture.
// This is not browser, screen-reader or device acceptance.
const languages=['pl','en','de','sk','cs','hu','ro','es','fr','it','uk','pt'];
for(const route of ['web/index.html','web/start/index.html'])test(`${route}: accessible names follow initial language and later changes`,()=>{
 const html=readFileSync(new URL('../'+route,import.meta.url),'utf8');
 const names=[...html.matchAll(/<[^>]+aria-label="[^"]+"[^>]*>/g)].map(([tag])=>{
  const attrs=Object.fromEntries([...tag.matchAll(/([\w-]+)="([^"]*)"/g)].map(m=>[m[1],m[2]]));
  return {attrs,getAttribute:k=>attrs[k]??null,setAttribute:(k,v)=>{attrs[k]=v;}};
 }).filter(n=>n.attrs['aria-label']!=='Fleet, Garage, Booking');
 assert.equal(names.length,4);
 for(const n of names)for(const lang of languages)assert.ok(n.attrs['data-aria-'+lang],`${n.attrs['aria-label']} lacks ${lang}`);
 const script=html.match(/<script>\s*([\s\S]*?)<\/script>/)[1];
 for(const initial of languages){
  let change;
  const selector={value:'en',options:[{text:'Language'}],selectedIndex:0,addEventListener:(_event,fn)=>{change=fn;}};
  const document={documentElement:{lang:'en'},title:'',getElementById:()=>selector,
   querySelector:()=>({}),querySelectorAll:q=>q==='[data-aria-en]'?names:[]};
  vm.runInNewContext(script,{document,navigator:{languages:[initial]},window:{localStorage:{getItem:()=>null,setItem(){}},location:{href:'https://flotaryx.com/',origin:'https://flotaryx.com'}},URL});
  const check=lang=>{assert.equal(document.documentElement.lang,lang);for(const n of names)assert.equal(n.attrs['aria-label'],n.attrs['data-aria-'+lang]);};
  check(initial);
  for(const lang of languages){selector.value=lang;change();check(lang);}
 }
});
