// Feature switches decided at build time. Centro de Inteligencia (Mario 2026-10-11, D0): Dirección, Inteligencia and Cierre contable
// stay HIDDEN in production until I5 is approved and executed — they are only on in staging, or where NEXT_PUBLIC_F360_INTEL = "on"
// is set explicitly. Hiding is not the security (every page re-checks in the database); it only avoids showing unfinished screens.
export const intelEnabled = () => process.env.NEXT_PUBLIC_F360_ENV === 'staging' || process.env.NEXT_PUBLIC_F360_INTEL === 'on';
export const INTEL_ROUTES = ['/direccion', '/inteligencia', '/cierre-contable'];

// Fuxia Academy (Sales A1, Mario 2026-10-11): on in staging, or where NEXT_PUBLIC_F360_ACADEMY = "on" is set explicitly (production
// only after P0-6 is closed and Mario approves). Same rule as above: hiding is not the security, every Academy RPC decides in the database.
export const academyEnabled = () => process.env.NEXT_PUBLIC_F360_ENV === 'staging' || process.env.NEXT_PUBLIC_F360_ACADEMY === 'on';
export const ACADEMY_ROUTES = ['/academy'];

// Growth P0 (Mario 2026-10-27: Instagram orgánico + registro de experimentos, autorizado SOLO en staging): the two Growth tabs are on
// in staging, or where NEXT_PUBLIC_F360_GROWTH_P0 = "on" is set explicitly (production only after Mario authorizes the pase and the
// migrations 20261104000100/0200 are applied there). Same rule: the database decides; hiding only avoids an unfinished tab.
export const growthP0Enabled = () => process.env.NEXT_PUBLIC_F360_ENV === 'staging' || process.env.NEXT_PUBLIC_F360_GROWTH_P0 === 'on';
