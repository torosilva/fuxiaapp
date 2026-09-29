// B4 revenue planning math (pure). Revenue = active customers × orders per customer × AOV.
// Everything returned is derived from the owner's ASSUMPTIONS; missing inputs give null (never a guessed value).

export type GrowthInputs = {
  active_customers?: number | null; orders_per_customer?: number | null; aov?: number | null;
  ecommerce_pct?: number | null; retail_pct?: number | null; shoes_pct?: number | null; accessories_pct?: number | null;
  new_pct?: number | null; returning_pct?: number | null; regions?: { name: string; pct: number }[]; note?: string | null;
};

export type Split = { label: string; pct: number | null; amount: number | null };

export type GrowthResult = {
  northStar: number;
  monthlyTarget: number;
  modeledRevenue: number | null;        // customers × frequency × AOV (the scenario's own revenue)
  gap: number | null;                   // North Star − modeled (positive = the scenario falls short)
  reachesTarget: boolean | null;
  ordersNeeded: number | null;          // North Star ÷ AOV
  customersNeeded: number | null;       // North Star ÷ (frequency × AOV)
  aovRequired: number | null;           // North Star ÷ (customers × frequency)
  frequencyRequired: number | null;     // North Star ÷ (customers × AOV)
  channel: Split[]; category: Split[]; customerType: Split[]; regions: Split[];
};

const pos = (x: number | null | undefined): x is number => typeof x === 'number' && Number.isFinite(x) && x > 0;
const div = (a: number, ...b: (number | null | undefined)[]) => (b.every(pos) ? a / (b as number[]).reduce((p, x) => p * x, 1) : null);

function split(ns: number, parts: [string, number | null | undefined][]): Split[] {
  const out: Split[] = parts.map(([label, pct]) => ({ label, pct: typeof pct === 'number' ? pct : null, amount: typeof pct === 'number' ? (ns * pct) / 100 : null }));
  const known = out.filter((s) => s.pct != null);
  if (known.length) {
    const rest = 100 - known.reduce((a, s) => a + (s.pct ?? 0), 0);
    if (rest > 0.0001) out.push({ label: 'Sin asignar', pct: rest, amount: (ns * rest) / 100 });
  }
  return out;
}

export function computeGrowth(northStar: number, i: GrowthInputs): GrowthResult {
  const modeled = pos(i.active_customers) && pos(i.orders_per_customer) && pos(i.aov) ? i.active_customers * i.orders_per_customer * i.aov : null;
  return {
    northStar,
    monthlyTarget: northStar / 12,
    modeledRevenue: modeled,
    gap: modeled == null ? null : northStar - modeled,
    reachesTarget: modeled == null ? null : modeled >= northStar,
    ordersNeeded: div(northStar, i.aov),
    customersNeeded: div(northStar, i.orders_per_customer, i.aov),
    aovRequired: div(northStar, i.active_customers, i.orders_per_customer),
    frequencyRequired: div(northStar, i.active_customers, i.aov),
    channel: split(northStar, [['Ecommerce', i.ecommerce_pct], ['Tiendas físicas', i.retail_pct]]),
    category: split(northStar, [['Zapatos', i.shoes_pct], ['Accesorios', i.accessories_pct]]),
    customerType: split(northStar, [['Nuevas clientas', i.new_pct], ['Recurrentes', i.returning_pct]]),
    regions: split(northStar, (i.regions ?? []).map((r) => [r.name, r.pct] as [string, number])),
  };
}
