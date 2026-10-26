#!/usr/bin/env node
/**
 * Read-only hosted Garage QA owner preflight using REAL Supabase Auth.
 * Requires the operator's disposable QA password + project public anon key
 * from local environment only. Never send credentials to GitHub Actions.
 * No Stripe, Checkout, SQL writes, service-role keys, or bypass tokens.
 */
import {pathToFileURL} from 'node:url';

const QA = 'https://fyestmquqvkdebxxbcky.supabase.co';
const OWNER = '304942d4-55f9-4053-a8b6-06a82573f68a';
const WORKSPACE = '57d0d3f7-5e86-4357-b724-de2d19abef42';

function publicKeyOnly(key) {
  if (typeof key !== 'string' || key.length > 2048) return false;
  if (/^sb_publishable_[A-Za-z0-9_-]+$/.test(key)) return true;
  const parts = key.split('.');
  if (parts.length !== 3 || !parts.every(x => /^[A-Za-z0-9_-]+$/.test(x))) return false;
  try { return JSON.parse(Buffer.from(parts[1], 'base64url').toString()).role === 'anon'; }
  catch { return false; }
}

async function parseJson(response, step) {
  if (!response.ok) throw new Error(step + ' returned HTTP ' + response.status);
  try {
    const obj = await response.json();
    if (obj && typeof obj === 'object' && !Array.isArray(obj)) return obj;
  } catch { /* never echo responses or credentials */ }
  throw new Error(step + ' returned invalid JSON');
}

export async function checkGarageQaOwner({email, password, anonKey}, request = fetch) {
  if (typeof email !== 'string' || !/^[^@\s]+@flotaryx\.test$/i.test(email) ||
      typeof password !== 'string' || password.length < 8 ||
      !publicKeyOnly(anonKey)) {
    throw new Error('Missing or invalid disposable QA credentials / publishable key');
  }
  const options = {redirect: 'error', signal: AbortSignal.timeout(15000)};
  const headers = {'Content-Type': 'application/json', apikey: anonKey};
  let token;
  let logoutAttempted = false;
  try {
    const authResponse = await request(QA + '/auth/v1/token?grant_type=password', {
      ...options, method: 'POST', headers, body: JSON.stringify({email, password}),
    });
    const auth = await parseJson(authResponse, 'Auth password sign-in');
    if (typeof auth.access_token !== 'string' ||
        !/^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(auth.access_token)) {
      throw new Error('Auth returned an unexpected session shape');
    }
    token = auth.access_token;
    const bearer = {...headers, Authorization: 'Bearer ' + token};
    const user = await parseJson(await request(QA + '/auth/v1/user', {
      ...options, method: 'GET', headers: bearer,
    }), 'Auth getUser');
    // Verify identity with the Auth server. Do not decode JWT or use
    // client-editable user_metadata for authorization.
    if (user.id !== OWNER || user.is_anonymous === true) {
      throw new Error('Signed-in account is NOT the designated Garage QA owner');
    }
    const status = await parseJson(await request(
      QA + '/functions/v1/flotaryx-garage-test-entitlement', {
        ...options, method: 'POST', headers: bearer,
        body: JSON.stringify({workspace_id: WORKSPACE}),
      },
    ), 'Entitlement read');
    const expectedKeys = ['access_ends_at', 'active', 'last_payment_state', 'source'];
    if (Object.keys(status).sort().join(',') !== expectedKeys.join(',') ||
        typeof status.active !== 'boolean' ||
        ![null, 'trial', 'paid'].includes(status.source) ||
        ![null, 'failed', 'paid'].includes(status.last_payment_state) ||
        !(status.access_ends_at === null ||
          (typeof status.access_ends_at === 'string' &&
           Number.isFinite(Date.parse(status.access_ends_at)))) ||
        (status.active && (status.source === null || status.access_ends_at === null)) ||
        (!status.active && (status.source !== null || status.access_ends_at !== null))) {
      throw new Error('Entitlement returned an unexpected or inconsistent status');
    }
    return {authVerified: true, correctOwner: true, entitlementReadable: true,
      activeAccess: status.active};
  } finally {
    // Best effort: logout revokes refresh token/server-side session but
    // issued access JWT may remain valid until its normal expiry.
    if (token) {
      try {
        logoutAttempted = true;
        await request(QA + '/auth/v1/logout?scope=local', {
          ...options, method: 'POST',
          headers: {...headers, Authorization: 'Bearer ' + token},
        });
      } catch { /* short-lived disposable QA credential only */ }
    }
    void logoutAttempted;
  }
}

async function main() {
  try {
    const result = await checkGarageQaOwner({
      email: process.env.FLOTARYX_QA_EMAIL,
      password: process.env.FLOTARYX_QA_PASSWORD,
      anonKey: process.env.FLOTARYX_QA_ANON_KEY,
    });
    console.log('PASS: QA real Auth, correct Garage owner and entitlement read');
    console.log('Access active:', result.activeAccess);
  } catch (e) {
    console.error('NO-GO:', e instanceof Error ? e.message : 'QA preflight failed');
    console.error('No Checkout, subscription, payment, or Stripe API was called.');
    process.exitCode = 1;
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  await main();
}
