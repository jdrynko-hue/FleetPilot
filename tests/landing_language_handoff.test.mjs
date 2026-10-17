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
      const links=['/app/','/app/?portal=fleet','/app/?portal=garage','/app/?portal=search#selection','https://other.test/app/','/privacy/'].map(href=>({
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
      }
    }
  });
}
