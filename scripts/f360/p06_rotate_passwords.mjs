// P0-6.2 · one-time rotation: every phone account {digits}@fuxia.app gets a random, never-stored password, so the old derived
// password fuxia_{tel}_{OTP_SALT} stops working everywhere. STAGING ONLY here (lib refuses production; production needs its own
// reviewed run). Lab accounts (+1 555 010 xxxx and @staging.invalid) are skipped: the lab suites set their own passwords.
// Run: scripts/s00a/run.sh ../f360/p06_rotate_passwords.mjs            (dry run: counts only)
//      scripts/s00a/run.sh ../f360/p06_rotate_passwords.mjs --apply
import { randomBytes } from 'node:crypto';
import { loadEnv, client, isLabEmail } from '../s00a/lib.mjs';

const env = loadEnv();
const c = client(env);
const apply = process.argv.includes('--apply');
const only = (process.argv.find((a) => a.startsWith('--only=')) ?? '').slice(7);   // rotate a single account (staging proof)
let page = 1, seen = 0, target = 0, done = 0, failed = 0;
for (;;) {
  const r = await fetch(`${env.api}/auth/v1/admin/users?per_page=500&page=${page}`, { headers: { apikey: env.service, Authorization: `Bearer ${env.service}` } }).then((x) => x.json());
  const users = r.users ?? [];
  if (!users.length) break;
  for (const u of users) {
    seen++;
    if (!/^\d{8,15}@fuxia\.app$/.test(u.email ?? '') || isLabEmail(u.email)) continue;
    if (only && u.email !== only) continue;
    target++;
    if (!apply) continue;
    const x = await c.admin.update(u.id, { password: randomBytes(32).toString('base64url') });
    if (x.ok) done++; else failed++;
  }
  page++;
}
console.log(JSON.stringify({ mode: apply ? 'apply' : 'dry-run', accounts_seen: seen, phone_accounts_to_rotate: target, rotated: done, failed }));
