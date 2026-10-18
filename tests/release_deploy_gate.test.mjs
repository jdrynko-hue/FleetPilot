import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const path = '.github/workflows/deploy.yml';
const yaml = readFileSync(path, 'utf8');
const eventBlock = yaml.split(/^permissions:/m,1)[0];
const buildBlock = yaml.split(/^  build:\s*$/m)[1]?.split(/^  deploy:\s*$/m)[0] || '';
const deployBlock = yaml.split(/^  deploy:\s*$/m)[1] || '';

test('publishing never triggers automatically on push or pull_request', () => {
  assert.match(eventBlock, /^on:\s*\n\s+workflow_dispatch:\s*$/m);
  assert.doesNotMatch(eventBlock, /^\s+push\s*:/m);
  assert.doesNotMatch(eventBlock, /^\s+pull_request\s*:/m);
  assert.doesNotMatch(eventBlock, /^\s+schedule\s*:/m);
});

test('release input requires explicit confirmation', () => {
  assert.match(eventBlock,/^\s+confirm_release:\s*$/m);
  assert.match(eventBlock,/^\s+required:\s+true\s*$/m);
  assert.match(buildBlock, /github\.event_name == 'workflow_dispatch'/);
  assert.match(buildBlock, /github\.ref == 'refs\/heads\/main'/);
  assert.match(buildBlock, /inputs\.confirm_release == 'PUBLISH-FLOTARYX'/);
});

test('deployment cannot run without the gated build', () => {
  assert.match(deployBlock,/^\s+needs:\s+build\s*$/m);
  assert.match(deployBlock,/actions\/deploy-pages@v4/);
  assert.match(buildBlock,/FLOTARYX_ECOSYSTEM_PRODUCTION=true/);
});

test('compiled production artifact must pass release validator before upload', () => {
  const validator = 'python3 tools/verify_release_candidate.py site';
  const upload = 'actions/upload-pages-artifact@v3';
  const checked = buildBlock.indexOf(validator);
  const uploaded = buildBlock.indexOf(upload);
  assert.ok(checked >= 0, 'release artifact validator is required');
  assert.ok(uploaded > checked, 'validator must run before the Pages artifact upload');
  assert.match(buildBlock,/git show HEAD:web\/index\.html/);
  assert.match(buildBlock,/cp -a build\/web\/. site\/app\//);
});
