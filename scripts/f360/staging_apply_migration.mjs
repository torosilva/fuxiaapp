// STAGING ONLY: applies ONE migration file + its schema_migrations row in a single transaction, without `db push`
// (so a peer session's pending migration is never dragged along). Refuses if the version is already recorded.
// Run: scripts/s00a/run.sh ../f360/staging_apply_migration.mjs supabase/migrations/<version>_<name>.sql
import { readFileSync } from 'node:fs';
import { basename } from 'node:path';
import { loadEnv, psql } from '../s00a/lib.mjs';

loadEnv();
const file = process.argv[2];
const m = /^(\d{14})_(.+)\.sql$/.exec(basename(file ?? ''));
if (!m) throw new Error('uso: staging_apply_migration.mjs supabase/migrations/<version>_<name>.sql');
const [, version, name] = m;
if (psql(`SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version = '${version}'`) !== '0') throw new Error(`ABORT: ${version} ya está aplicada en staging`);
const body = readFileSync(file, 'utf8');
psql(`BEGIN;\n${body}\nINSERT INTO supabase_migrations.schema_migrations (version, name, statements) VALUES ('${version}', '${name.replace(/'/g, '')}', '{}');\nCOMMIT;\n`);
console.log(`APLICADA en staging: ${version} ${name}`);
