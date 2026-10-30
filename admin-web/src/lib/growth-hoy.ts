import { rpc } from '@/lib/f360';
import type { Competencia, Hoy, Recuperar } from '@/lib/growth-hoy-labels';

// Growth → Hoy, Clientas y Competencia: server-side readers (the rules live in the database).
export * from '@/lib/growth-hoy-labels';
export const getHoy = () => rpc<Hoy>('f360_growth_hoy');
export const getRecuperar = (market: 'MX' | 'CO') => rpc<Recuperar>('f360_growth_recuperar', { p_market: market });
export const getCompetencia = () => rpc<Competencia>('f360_growth_competencia');
