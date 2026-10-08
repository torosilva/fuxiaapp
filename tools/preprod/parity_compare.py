#!/usr/bin/env python3
"""Compare two parity fingerprints (tools/preprod/parity_catalog.sql output): staging psql text and prod_read JSON.
Usage: python3 -I parity_compare.py <staging.txt> <prod.json>  → prints differences grouped by kind, and S-G0/SB0 classification."""
import json, re, sys
from collections import defaultdict

def load_staging(p):
    t = open(p).read()
    i = t.index('[')
    return json.loads(t[i:t.rindex(']') + 1])

def load_prod(p):
    d = json.loads(open(p).read())
    return d[0]['fp']

s = {(r['k'], r['id']): r['h'] for r in load_staging(sys.argv[1])}
p = {(r['k'], r['id']): r['h'] for r in load_prod(sys.argv[2])}

SG0 = re.compile(r"(sg0|measurement_|marketing_spend|fx_rate|product_cost|legacy_store_sale|legacy_sale_check|reconcile|commerce_source_health|f360_channel_mode|bazaar_|tax_status)", re.I)
def expected(k, i):
    if re.search(r"commerce_sync_runs_kind_check", i): return 'S-G0 (kind + reconcile)'
    if re.search(r"public\.f360_(favorites_report|review_summary|stock_demand|store_order)\(", i): return 'SB0 D13 (viewer→operator)'
    if i.startswith('f360_board') or 'f360_board' in i: return 'SB0'
    if k == 'migration' and (i.startswith('20261014') or i.startswith('20261015') or i.startswith('20261016')): return 'S-G0/SB0/preprod'
    if SG0.search(i): return 'S-G0'
    return None

only_s, only_p, diff = defaultdict(list), defaultdict(list), defaultdict(list)
for key in sorted(set(s) | set(p)):
    k, i = key
    if key not in p: only_s[k].append(i)
    elif key not in s: only_p[k].append(i)
    elif s[key] != p[key]: diff[k].append(i)

def show(title, d):
    print(f"\n## {title}")
    tot = sum(len(v) for v in d.values())
    if not tot: print("(none)"); return
    for k in sorted(d):
        for i in d[k]:
            e = expected(k, i)
            print(f"- [{k}] {i}" + (f"  → expected ({e})" if e else "  → UNEXPECTED"))

print(f"objects: staging={len(s)} production={len(p)}")
show("Only in STAGING", only_s)
show("Only in PRODUCTION", only_p)
show("Different definition", diff)
