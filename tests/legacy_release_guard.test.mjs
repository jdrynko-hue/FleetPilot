import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const legacyInstallers = [
  '.github/workflows/flotaryx-billing-oneclick.yml',
  '.github/workflows/flotaryx-billing-fixed-installer.yml',
];

/** These legacy jobs can push to main and must not bypass the release gate. */
function legacySafetyFailures(yaml) {
  const failures = [];
  const trigger = yaml.split(/^permissions:/m, 1)[0];
  const permissions = yaml.split(/^permissions:\s*$/m)[1]
    ?.split(/^(?:concurrency|jobs):/m)[0] ?? '';
  const job = yaml.split(/^  install:\s*$/m)[1]
    ?.split(/^  [\w-]+:\s*$/m)[0] ?? '';

  if (!/^on:\s*\n\s+workflow_dispatch:\s*$/m.test(trigger)
      || /^\s+(?:push|pull_request|schedule|workflow_call)\s*:/m.test(trigger)) {
    failures.push('legacy installer has an unexpected trigger');
  }
  if (!/^  contents:\s*read\s*$/m.test(permissions)
      || /^\s*(?:contents|pages|actions|id-token):\s*write\s*$/m.test(permissions)) {
    failures.push('legacy installer retains write privileges');
  }
  if (!/^    if:\s*\$\{\{\s*false\s*\}\}\s*$/m.test(job)) {
    failures.push('legacy installer job is not explicitly disabled');
  }
  return failures;
}

for (const path of legacyInstallers) {
  test(path + ' is disabled and read-only', () => {
    assert.deepEqual(legacySafetyFailures(readFileSync(path, 'utf8')), []);
  });
}

const fixture = String.raw`name: Example installer
on:
  workflow_dispatch:
permissions:
  contents: read
jobs:
  install:
    if: ${{ false }}
    runs-on: ubuntu-latest
`;

test('guard refuses absent job disabling', () => {
  assert.ok(legacySafetyFailures(fixture.replace(/    if:.*\n/, '')).length > 0);
});
test('guard refuses direct Pages or repository write privileges', () => {
  assert.ok(legacySafetyFailures(fixture.replace('contents: read', 'contents: write')).length > 0);
  assert.ok(legacySafetyFailures(fixture.replace('contents: read', 'contents: read\n  pages: write')).length > 0);
});
test('guard refuses automatic push triggers', () => {
  assert.ok(legacySafetyFailures(fixture.replace(
    '  workflow_dispatch:', '  push:\n    branches: [main]\n  workflow_dispatch:')).length > 0);
});
