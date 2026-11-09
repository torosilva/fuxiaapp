#!/usr/bin/env bash
# Fuxia 360 · the old WooCommerce store's contacts → a CSV in Shopify's own customer-import format (Mario 2026-11-09: migrate
# what we had, using Shopify's native tools: Customers → Import). READ-ONLY on the server. The CSV holds personal data, so it is
# written ONLY to ~/fuxia360-respaldos/ (chmod 600), never to the repo, and this script prints counts only.
# Sources (México only — Colombia still sells on WooCommerce with its own popup):
#   · cnv_fuxia_leads (popup "10% en tu primera compra", "Sin spam. Puedes darte de baja cuando quieras.") → accepts e-mail
#     marketing = yes. The optional WhatsApp gave Club points, not SMS consent → SMS = no.
#   · cnv_wc_customer_lookup (buyers / accounts, country MX) → no marketing consent (unless they are also popup leads).
#   · cnv_cartflows_ca_cart_abandonment (carts never completed) → no marketing consent.
# One row per e-mail; consent is "yes" only when the person subscribed through the popup. Tags say where each one came from.
# Run (Mario, SSH to production): scripts/f360/wp_clientas_a_shopify.sh   → then Shopify admin → Customers → Import.
set -euo pipefail
SSH=(ssh -p 18765 -o BatchMode=yes u2262-72gcmsiaboij@ssh.fuxiaballerinas.com)
WP='~/www/fuxiaballerinas.com/public_html'
OUT_DIR="$HOME/fuxia360-respaldos"; mkdir -p "$OUT_DIR"; chmod 700 "$OUT_DIR"
TMP="$(mktemp -d)"; chmod 700 "$TMP"; trap 'rm -rf "$TMP"' EXIT
q() { "${SSH[@]}" "cd $WP && test \"\$(wp option get home)\" = 'https://fuxiaballerinas.com' && wp db query \"$1\" --skip-column-names --batch"; }
q "SELECT email, IFNULL(telefono,''), IFNULL(pais,''), creado FROM cnv_fuxia_leads" > "$TMP/leads.tsv"
q "SELECT email, IFNULL(first_name,''), IFNULL(last_name,''), IFNULL(billing_phone,''), IFNULL(city,''), IFNULL(state,''), IFNULL(postcode,''), IFNULL(country,'') FROM cnv_wc_customer_lookup" > "$TMP/clientes.tsv"
q "SELECT email, REPLACE(REPLACE(REPLACE(IFNULL(other_fields,''), CHAR(9), ' '), CHAR(10), ' '), CHAR(13), ' '), order_status, time FROM cnv_cartflows_ca_cart_abandonment WHERE order_status <> 'completed'" > "$TMP/carritos.tsv"
python3 -I - "$TMP" "$OUT_DIR/shopify_clientas_mx.csv" <<'PY'
import csv, re, sys, os
tmp, out = sys.argv[1], sys.argv[2]
bad = 0
def rows(n, k):
    # newline='\n': a stray \r inside a field must not split the row (Python's default splits on \r too)
    global bad
    out = []
    with open(os.path.join(tmp, n), encoding='utf-8', errors='replace', newline='\n') as f:
        for l in f:
            c = l.rstrip('\r\n').split('\t')
            if not l.strip(): continue
            if len(c) != k: bad += 1; continue
            out.append(c)
    return out
email_ok = re.compile(r'^[^@\s]+@[^@\s]+\.[a-z]{2,}$', re.I)
def phone_mx(p):
    d = re.sub(r'\D', '', p or '')
    if len(d) == 10: return '+52' + d
    if len(d) == 12 and d.startswith('52'): return '+' + d
    if len(d) == 13 and d.startswith('521'): return '+52' + d[3:]
    return ''
people = {}
def get(e):
    e = (e or '').strip().lower()
    if not email_ok.match(e): return None
    return people.setdefault(e, {'email': e, 'first': '', 'last': '', 'phone': '', 'city': '', 'state': '', 'zip': '', 'consent': False, 'tags': set(), 'mx': False})
skipped_co = 0
for e, tel, pais, creado in rows('leads.tsv', 4):
    if pais.strip().lower() == 'co': skipped_co += 1; continue
    p = get(e)
    if not p: continue
    p['consent'] = True; p['mx'] = True; p['tags'].add('popup-bienvenida-woo')
    p['phone'] = p['phone'] or phone_mx(tel)
for e, fn, ln, ph, city, st, zp, country in rows('clientes.tsv', 8):
    if country.strip().upper() not in ('MX', ''): continue
    p = get(e)
    if not p: continue
    p['mx'] = True; p['tags'].add('clienta-woo')
    p['first'] = p['first'] or fn.strip(); p['last'] = p['last'] or ln.strip()
    p['phone'] = p['phone'] or phone_mx(ph); p['city'] = p['city'] or city.strip(); p['state'] = p['state'] or st.strip(); p['zip'] = p['zip'] or zp.strip()
for e, other, status, t in rows('carritos.tsv', 4):
    # other_fields is a PHP-serialized array; only name, phone and country are read from it
    def field(k):
        m = re.search(r'"' + k + r'";s:\d+:"([^"]*)"', other)
        return m.group(1) if m else ''
    country = field('wcf_billing_country') or field('wcf_location')
    if country and country.upper() not in ('MX', 'MEXICO', 'MÉXICO'): continue
    p = get(e)
    if not p: continue
    p['mx'] = True; p['tags'].add('carrito-abandonado-woo')
    p['first'] = p['first'] or field('wcf_first_name'); p['last'] = p['last'] or field('wcf_last_name')
    p['phone'] = p['phone'] or phone_mx(field('wcf_phone_number'))
seen_phones = set()
head = ['First Name', 'Last Name', 'Email', 'Accepts Email Marketing', 'Default Address Company', 'Default Address Address1', 'Default Address Address2',
        'Default Address City', 'Default Address Province Code', 'Default Address Country Code', 'Default Address Zip', 'Default Address Phone',
        'Phone', 'Accepts SMS Marketing', 'Tags', 'Note', 'Tax Exempt']
n = {'total': 0, 'con_permiso': 0, 'sin_permiso': 0, 'con_celular': 0}
fd = os.open(out, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
with os.fdopen(fd, 'w', newline='', encoding='utf-8') as f:
    w = csv.writer(f); w.writerow(head)
    for p in people.values():
        if not p['mx']: continue
        ph = p['phone'] if p['phone'] and p['phone'] not in seen_phones else ''   # Shopify rejects a phone used twice
        if ph: seen_phones.add(ph); n['con_celular'] += 1
        w.writerow([p['first'], p['last'], p['email'], 'yes' if p['consent'] else 'no', '', '', '', '', '', '', '', '',   # no address: Woo state codes (DF, JA…) differ from Shopify's and would reject the row; addresses stay in Fuxia 360
                    ph, 'no', ', '.join(sorted(p['tags'])), 'Migrada de la tienda WooCommerce (2026-11)', 'no'])
        n['total'] += 1; n['con_permiso' if p['consent'] else 'sin_permiso'] += 1
print(f"CSV listo: {out}")
print(f"clientas: {n['total']} · aceptan correos: {n['con_permiso']} · sin permiso de publicidad: {n['sin_permiso']} · con celular: {n['con_celular']} · leads de Colombia que se quedan en Woo: {skipped_co} · renglones ilegibles omitidos: {bad}")
PY
