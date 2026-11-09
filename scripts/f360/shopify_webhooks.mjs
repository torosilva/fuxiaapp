// Shopify México → Fuxia 360: subscribes the order webhooks (orders/create, orders/updated) to the PRODUCTION function
// f360-shopify. Without --apply it only lists what exists and what it would create. Idempotent: an existing subscription to
// the same URL is left alone. Credentials from ~/.fuxia-shopify.client_id / ~/.fuxia-shopify.secret (never printed).
// Run AFTER `scripts/f360/deploy_prod_function.sh f360-shopify`:  node scripts/f360/shopify_webhooks.mjs [--apply]
import { readFileSync } from 'node:fs';
import { homedir } from 'node:os';

const SHOP = 'z9fdqc-0z.myshopify.com';
const API = '2026-10';
const URI = 'https://tgzgiwfzddsghnxgkcqd.supabase.co/functions/v1/f360-shopify';
const TOPICS = ['ORDERS_CREATE', 'ORDERS_UPDATED'];
const apply = process.argv.includes('--apply');

const read = (f) => readFileSync(`${homedir()}/${f}`, 'utf8').trim();
const tokenRes = await fetch(`https://${SHOP}/admin/oauth/access_token`, {
  method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
  body: new URLSearchParams({ grant_type: 'client_credentials', client_id: read('.fuxia-shopify.client_id'), client_secret: read('.fuxia-shopify.secret') }),
});
if (!tokenRes.ok) throw new Error(`Shopify token → ${tokenRes.status}`);
const { access_token: token } = await tokenRes.json();
async function gql(query, variables) {
  const r = await fetch(`https://${SHOP}/admin/api/${API}/graphql.json`, {
    method: 'POST', headers: { 'Content-Type': 'application/json', 'X-Shopify-Access-Token': token }, body: JSON.stringify({ query, variables }),
  });
  const j = await r.json();
  if (!r.ok || j.errors) throw new Error(`Shopify GraphQL → ${r.status} ${JSON.stringify(j.errors ?? j).slice(0, 400)}`);
  return j.data;
}

const existing = (await gql(`{ webhookSubscriptions(first: 50) { nodes { id topic uri } } }`)).webhookSubscriptions.nodes;
for (const w of existing) console.log(`existe: ${w.topic} → ${w.uri}`);
for (const topic of TOPICS) {
  if (existing.some((w) => w.topic === topic && w.uri === URI)) { console.log(`ya está: ${topic}`); continue; }
  if (!apply) { console.log(`crearía: ${topic} → ${URI}`); continue; }
  const d = await gql(`mutation($topic: WebhookSubscriptionTopic!, $uri: String!) {
      webhookSubscriptionCreate(topic: $topic, webhookSubscription: { uri: $uri, format: JSON }) { webhookSubscription { id topic uri } userErrors { field message } } }`,
    { topic, uri: URI });
  const r = d.webhookSubscriptionCreate;
  if (r.userErrors.length) throw new Error(`${topic}: ${JSON.stringify(r.userErrors)}`);
  console.log(`creado: ${r.webhookSubscription.topic} → ${r.webhookSubscription.uri}`);
}
console.log(apply ? 'LISTO' : 'Solo lectura (usa --apply para crear).');
