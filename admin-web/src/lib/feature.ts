// Feature switches decided at build time. Centro de Inteligencia (Mario 2026-10-11, D0): Dirección, Inteligencia and Cierre contable
// stay HIDDEN in production until I5 is approved and executed — they are only on in staging, or where NEXT_PUBLIC_F360_INTEL = "on"
// is set explicitly. Hiding is not the security (every page re-checks in the database); it only avoids showing unfinished screens.
export const intelEnabled = () => process.env.NEXT_PUBLIC_F360_ENV === 'staging' || process.env.NEXT_PUBLIC_F360_INTEL === 'on';
export const INTEL_ROUTES = ['/direccion', '/inteligencia', '/cierre-contable'];
