import './landing_accessible_names.test.mjs';
import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';

const languages=['pl','en','de','sk','cs','hu','ro','es','fr','it','uk','pt'];
for(const file of ['web/index.html','web/start/index.html']) {
  test(`${file}: selected language follows every portal link, including restricted storage`,()=>{
    const html=readFileSync(file,'utf8');
    const code=html.slice(html.indexOf('  function canonical('),html.indexOf("  selector.addEventListener('change'"));
    assert.ok(code.includes('function translate'));
    for(const restricted of [false,true]) {
      const links=['/app/','/app/?portal=fleet','/app/?portal=garage','/app/?portal=search#selection','https://other.test/app/','/privacy/','/install/?from=home#android','/start/','/?campaign=uk','#features'].map(href=>({
        href,getAttribute(){return this.href;},setAttribute(_,value){this.href=value;}
      }));
      const context={URL,supported:languages,items:[],groupVehicleHeading(){},stepWords:{},
        selector:{options:[{text:'Language'}],selectedIndex:0},
        document:{documentElement:{},querySelectorAll:s=>s==='a[href]'?links:[]},
        window:{location:new URL('https://example.test/'),localStorage:{setItem(){if(restricted)throw Error('Blocked');}}}};
      vm.createContext(context);
      vm.runInContext(code,context);
      for(const language of languages) {
        vm.runInContext(`translate('${language}')`,context);
        for(let i=0;i<4;i++) {
          const url=new URL(links[i].href,context.window.location);
          assert.equal(url.searchParams.get('lang'),language);
          assert.equal(url.searchParams.getAll('lang').length,1);
          assert.equal(url.searchParams.get('portal'),[null,'fleet','garage','search'][i]);
        }
        assert.equal(new URL(links[3].href,context.window.location).hash,'#selection');
        assert.equal(links[4].href,'https://other.test/app/');
        assert.equal(links[5].href,'/privacy/');
        for(const i of [6,7,8])assert.equal(new URL(links[i].href,context.window.location).searchParams.get('lang'),language);
        assert.equal(new URL(links[6].href,context.window.location).searchParams.get('from'),'home');
        assert.equal(new URL(links[6].href,context.window.location).hash,'#android');
        assert.equal(new URL(links[8].href,context.window.location).searchParams.get('campaign'),'uk');
        assert.equal(links[9].href,'#features');
      }
    }
  });
}

function languagePage(file,{query='',saved=null,browser=['en-GB'],restricted=false}={}){
  const html=readFileSync(file,'utf8');
  const script=html.match(/<script>\s*([\s\S]*?)<\/script>/)[1];
  const links=['/app/?portal=garage#selection','/','/start/','https://other.test/app/','#features'].map(href=>({
    href,getAttribute(){return this.href;},setAttribute(_,value){this.href=value;}
  }));
  const buttons=['en','pl'].map(lang=>({dataset:{lang},setAttribute(){},addEventListener(_,fn){this.select=fn;}}));
  const selector={value:'en',options:[{text:'Language'}],selectedIndex:0,addEventListener(_,fn){this.select=fn;}};
  const document={documentElement:{lang:'en'},title:'',getElementById:()=>selector,querySelector:()=>({}),
    querySelectorAll:q=>q==='a[href]'?links:q==='.lang button'?buttons:[]};
  let stored=saved;
  const window={location:new URL(`https://flotaryx.com/${file.includes('/install/')?'install/':''}${query}`),
    localStorage:{getItem(){if(restricted)throw Error('Blocked');return stored;},
      setItem(_,value){if(restricted)throw Error('Blocked');stored=value;}}};
  vm.runInNewContext(script,{document,window,navigator:{languages:browser},URL});
  return {document,links,buttons,selector,stored:()=>stored};
}

for(const file of ['web/index.html','web/start/index.html'])test(`${file}: explicit language wins over stored and browser language`,()=>{
  for(const language of languages){
    const page=languagePage(file,{query:`?lang=${language.toUpperCase()}-XX`,saved:'en',browser:['de-DE']});
    assert.equal(page.document.documentElement.lang,language);
    assert.equal(new URL(page.links[0].href,'https://flotaryx.com').searchParams.get('lang'),language);
  }
  assert.equal(languagePage(file,{query:'?lang=unsupported',saved:'pl',browser:['de-DE']}).document.documentElement.lang,'pl');
});

test('install guide preserves selected language through restricted storage and fallback translation',()=>{
  const cases=[
    {query:'?lang=pl-PL',saved:'en',browser:['en-GB'],expected:'pl',handoff:'pl'},
    {query:'?lang=en',saved:'pl',browser:['pl-PL'],expected:'en',handoff:'en'},
    {query:'?lang=xx',saved:'pl',browser:['en-GB'],expected:'pl',handoff:'pl'},
    {saved:'pl',browser:['en-GB'],expected:'pl',handoff:'pl'},
    {query:'?lang=pl',restricted:true,expected:'pl',handoff:'pl'},
    {restricted:true,browser:['pl-PL'],expected:'pl',handoff:'pl'},
    {query:'?lang=de',saved:'pl',expected:'en',handoff:'de'},
    {saved:'fr',expected:'en',handoff:'fr'},
    {browser:['xx','pt-PT'],expected:'en',handoff:'pt'},
  ];
  for(const options of cases){
    const page=languagePage('web/install/index.html',options);
    assert.equal(page.document.documentElement.lang,options.expected);
    for(const link of page.links.slice(0,3))assert.equal(new URL(link.href,'https://flotaryx.com').searchParams.get('lang'),options.handoff);
    assert.equal(new URL(page.links[0].href,'https://flotaryx.com').searchParams.get('portal'),'garage');
    assert.equal(new URL(page.links[0].href,'https://flotaryx.com').hash,'#selection');
    assert.equal(page.links[3].href,'https://other.test/app/');
    assert.equal(page.links[4].href,'#features');
    assert.equal(page.stored(),options.saved??null,'initial fallback must not change the saved preference');
    page.buttons[1].select();
    assert.equal(page.document.documentElement.lang,'pl');
    assert.equal(new URL(page.links[0].href,'https://flotaryx.com').searchParams.get('lang'),'pl');
    if(!options.restricted)assert.equal(page.stored(),'pl');
  }
});
