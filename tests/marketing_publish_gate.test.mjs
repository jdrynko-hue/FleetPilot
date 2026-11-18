import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';

const workflow = readFileSync('.github/workflows/publish-approved-marketing.yml', 'utf8');
const trigger = workflow.split(/^permissions:/m)[0];
const prepare = workflow.split(/^  prepare:\s*$/m)[1].split(/^  deploy:\s*$/m)[0];
const deploy = workflow.split(/^  deploy:\s*$/m)[1];

test('marketing publication remains manual, main-only and explicitly confirmed', () => {
  assert.match(trigger, /^on:\s*\n\s+workflow_dispatch:\s*$/m);
  assert.doesNotMatch(trigger, /^\s+(?:push|pull_request|schedule|workflow_run|workflow_call|repository_dispatch):/m);
  assert.match(trigger, /required: true/);
  assert.match(prepare, /github\.event_name == 'workflow_dispatch'/);
  assert.match(prepare, /github\.ref == 'refs\/heads\/main'/);
  assert.match(prepare, /inputs\.confirm_release == 'PUBLISH-MARKETING-d505b1a0'/);
});

test('the approved manifest and exact source are pinned', () => {
  const manifest = readFileSync('docs/releases/2026-11-18-approved-marketing.json');
  const digest = createHash('sha256').update(manifest).digest('hex');
  assert.match(workflow, new RegExp(`APPROVAL_SHA256: ${digest}`));
  assert.match(prepare, /ref: deb7643c4bf84251d1de3bc2818cd1ede4194a56/);
  assert.match(prepare, /artifact-ids: '14443664409'/);
  assert.match(prepare, /run-id: '44343745692'/);
  assert.doesNotMatch(workflow, /flutter (?:build|create)|flutter-action|supabase db|npm install/);
});

test('only deployment can publish after exact staging and public preflight', () => {
  assert.doesNotMatch(prepare, /pages: write|id-token: write|deploy-pages/);
  assert.match(deploy, /^\s+needs: prepare$/m);
  assert.ok(prepare.indexOf('publish_approved_marketing.py stage') < prepare.indexOf('actions/upload-pages-artifact'));
  assert.ok(deploy.indexOf('--phase baseline') < deploy.indexOf('actions/deploy-pages'));
  assert.ok(deploy.indexOf('--phase release') > deploy.indexOf('actions/deploy-pages'));
  assert.match(deploy, /artifact_name: approved-marketing-pages/);
  assert.match(workflow, /group: pages\n\s+cancel-in-progress: false/);
});

test('review workflow cannot publish or change the repository', () => {
  const review = readFileSync('.github/workflows/marketing-publish-review.yml', 'utf8');
  assert.doesNotMatch(review, /pages: write|id-token: write|contents: write|deploy-pages|upload-pages-artifact/);
  assert.match(review, /--phase baseline/);
  assert.match(review, /include-hidden-files: true/);
});
