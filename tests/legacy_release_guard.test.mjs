import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync, readdirSync} from 'node:fs';

const directory = '.github/workflows/';
const legacyInstallers = JSON.parse(readFileSync('tests/fixtures/archived_installers.json', 'utf8'));

// Archived files deliberately use one canonical block-style YAML envelope.
// Reject alternate syntax rather than interpreting arbitrary YAML with regexes.
function legacySafetyFailures(yaml) {
  const failures = [];
  const envelope = yaml.slice(0, yaml.indexOf('\njobs:'));
  const activeLines = envelope.split('\n').filter(line => line.trim() && !line.trimStart().startsWith('#'));
  function block(key) {
    const start = activeLines.indexOf(key + ':');
    if (start < 0) return '';
    const end = activeLines.findIndex((line, index) => index > start && /^\S/.test(line));
    return activeLines.slice(start, end < 0 ? undefined : end).join('\n');
  }
  if (block('on') !== 'on:\n  workflow_dispatch:') {
    failures.push('legacy installer has an unexpected trigger');
  }
  if (block('permissions') !== 'permissions:\n  contents: read') {
    failures.push('legacy installer must have only read-only repository permission');
  }
  for (const key of ['on', 'permissions', 'jobs']) {
    if ((yaml.match(new RegExp(`^${key}:`, 'gm')) ?? []).length !== 1) failures.push(`unexpected ${key} map`);
  }
  const jobsText = yaml.split(/^jobs:\s*$/m)[1] ?? '';
  const jobHeaders = [...jobsText.matchAll(/^  \S[^\n]*$/gm)];
  if (!jobHeaders.length) failures.push('missing canonical job map');
  for (let index = 0; index < jobHeaders.length; index++) {
    const header = jobHeaders[index];
    const job = jobsText.slice(header.index, jobHeaders[index + 1]?.index);
    const conditions = job.match(/^    if:[^\n]*$/gm) ?? [];
    if (!/^  [\w-]+:$/.test(header[0]) || conditions.length !== 1 || conditions[0] !== '    if: ${{ false }}') {
      failures.push(`legacy job ${header[0].trim()} is not explicitly disabled`);
    }
    if (/^    (?:permissions|uses|<<):/m.test(job)) failures.push('job changes its permission or execution boundary');
  }
  return failures;
}

for (const name of legacyInstallers) {
  test(name + ' is disabled and read-only', () => {
    assert.deepEqual(legacySafetyFailures(readFileSync(directory + name, 'utf8')), []);
  });
}

test('every repository-writing workflow is inventoried as an archived installer', () => {
  for (const name of readdirSync(directory).filter(name => /\.ya?ml$/.test(name))) {
    const yaml = readFileSync(directory + name, 'utf8');
    // Includes job-level grants and installers whose grants have been removed.
    if (/\bcontents\s*:\s*write\b|\bpermissions\s*:\s*write-all\b|\bgit\s+push\b/.test(yaml)) {
      assert.ok(legacyInstallers.includes(name), `${name} adds an unreviewed repository writer`);
    }
  }
});

const fixture = `name: Example installer
on:
  workflow_dispatch:
permissions:
  contents: read
jobs:
  install:
    if: \${{ false }}
    runs-on: ubuntu-latest
`;

test('guard accepts the canonical archived envelope', () => {
  assert.deepEqual(legacySafetyFailures(fixture), []);
});
for (const [name, mutate] of [
  ['absent job disabling', text => text.replace(/    if:.*\n/, '')],
  ['a second enabled job', text => text + '  publish:\n    runs-on: ubuntu-latest\n'],
  ['a condition that can enable a job', text => text.replace('${{ false }}', '${{ true }}')],
  ['duplicate conditions', text => text.replace('    runs-on:', '    if: true\n    runs-on:')],
  ['inline job syntax', text => text.replace(/  install:[\s\S]*/, '  install: {runs-on: ubuntu-latest}\n')],
  ['repository writes', text => text.replace('contents: read', 'contents: write')],
  ['Pages writes', text => text.replace('contents: read', 'contents: read\n  pages: write')],
  ['implicit permission inheritance', text => text.replace('permissions:\n  contents: read\n', '')],
  ['job-level permission override', text => text.replace('    runs-on:', '    permissions:\n      contents: write\n    runs-on:')],
  ['automatic push', text => text.replace('  workflow_dispatch:', '  push:\n    branches: [main]\n  workflow_dispatch:')],
  ['reusable execution', text => text.replace('  workflow_dispatch:', '  workflow_call:')],
  ['scheduled execution', text => text.replace('  workflow_dispatch:', '  schedule:\n    - cron: "0 * * * *"')],
]) {
  test(`guard refuses ${name}`, () => assert.ok(legacySafetyFailures(mutate(fixture)).length > 0));
}
