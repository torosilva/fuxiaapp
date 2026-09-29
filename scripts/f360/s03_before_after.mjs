import { readFileSync } from 'node:fs';
import { loadEnv, psql } from '../s00a/lib.mjs';
loadEnv();
console.log(psql(readFileSync('supabase/staging/f360_s03_before_after_probe.sql', 'utf8')).split('\n').filter((l) => / \| /.test(l)).join('\n'));
