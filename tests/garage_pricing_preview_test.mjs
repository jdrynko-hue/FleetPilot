// Evaluates the preview's embedded pricing script with a small fake DOM.
// No browser, network, payment APIs or package dependencies are required.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';

const markup = readFileSync(
  new URL('../design/garage-pricing-preview/index.html', import.meta.url), 'utf8',
);
const script = markup.match(/<script>([\s\S]*?)<\/script>/)?.[1];
assert.ok(script, 'Preview needs the pricing script');

const nodes = new Map();
const get = (id) => {
  if (!nodes.has(id)) {
    nodes.set(id, {
      value: id === 'market' ? 'UK' : id === 'language' ? 'en' : '',
      textContent: '',
      attrs: {},
      handlers: {},
      dataset: {},
      setAttribute(key, value) { this.attrs[key] = value; },
      addEventListener(event, callback) { this.handlers[event] = callback; },
      append(...children) {
        this.textContent += children.map((child) => child.textContent).join('');
      },
    });
  }
  return nodes.get(id);
};
const document = {
  documentElement: { lang: 'en' },
  getElementById: get,
  querySelectorAll: () => [
    { dataset: { i18n: 'headline' }, textContent: '' },
    { dataset: { i18n: 'coming' }, textContent: '' },
  ],
  createTextNode: (value) => ({ textContent: value }),
  createElement: () => ({ textContent: '' }),
};
runInNewContext(script, { document, console, Object, String });

assert.match(get('starter-price').textContent, /£39/);
assert.match(get('team-price').textContent, /£79/);
assert.equal(get('monthly').attrs['aria-pressed'], 'true');

get('yearly').handlers.click();
assert.equal(get('yearly').attrs['aria-pressed'], 'true');
assert.match(get('starter-price').textContent, /£32\.50/);
assert.match(get('team-term').textContent, /£790/);
assert.match(get('pro-term').textContent, /£1,390/);

get('market').value = 'EU';
get('market').handlers.change();
assert.match(get('team-price').textContent, /€74\.17/);
assert.match(get('pro-term').textContent, /€1,590/);

get('market').value = 'PL';
get('market').handlers.change();
assert.match(get('starter-price').textContent, /82,50 zł/);
assert.match(get('team-term').textContent, /2\s?190 zł/);

get('language').value = 'pl';
get('language').handlers.change();
assert.equal(document.documentElement.lang, 'pl');
assert.match(get('starter-term').textContent, /przed podatkiem/);

get('monthly').handlers.click();
assert.match(get('starter-price').textContent, /99 zł/);
assert.match(get('pro-price').textContent, /399 zł/);
assert.equal(get('yearly').attrs['aria-pressed'], 'false');

console.log('Garage prototype: all dynamic market, term and language checks PASS.');
