-- Pre-production gate S-G0/SB0 · schema parity fingerprint (READ-ONLY catalog query, no data, no PII, no secret values).
-- One SELECT, no semicolons: runs as-is on staging (psql) and on production (scripts/f360/prod_read.sh).
-- Each row = kind | identity | md5 of the definition. Compare with tools/preprod/parity_compare.py.
select coalesce(json_agg(json_build_object('k', k, 'id', id, 'h', h) order by k, id), '[]') as fp from (
  select 'table' k, n.nspname || '.' || c.relname id,
         md5(string_agg(a.attname || ':' || format_type(a.atttypid, a.atttypmod) || ':' || a.attnotnull || ':' || coalesce(pg_get_expr(d.adbin, d.adrelid), ''), ',' order by a.attnum)) h
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  join pg_attribute a on a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped
  left join pg_attrdef d on d.adrelid = c.oid and d.adnum = a.attnum
  where n.nspname in ('public', 'f360', 'f360_board') and c.relkind in ('r', 'p')
  group by 1, 2
  union all
  select 'view', n.nspname || '.' || c.relname, md5(pg_get_viewdef(c.oid))
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname in ('public', 'f360', 'f360_board') and c.relkind in ('v', 'm')
  union all
  select 'function', n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')',
         md5(pg_get_functiondef(p.oid))
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname in ('public', 'f360', 'f360_board') and p.prokind in ('f', 'p')
    and not exists (select 1 from pg_depend dp where dp.objid = p.oid and dp.deptype = 'e')
  union all
  select 'function_acl', n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')',
         md5(coalesce((select string_agg(x, ',' order by x) from unnest(p.proacl::text[]) x where x !~ '^(postgres|supabase_admin)='), ''))
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname in ('public', 'f360', 'f360_board') and p.prokind in ('f', 'p')
    and not exists (select 1 from pg_depend dp where dp.objid = p.oid and dp.deptype = 'e')
  union all
  select 'trigger', t.tgrelid::regclass::text || '.' || t.tgname, md5(pg_get_triggerdef(t.oid))
  from pg_trigger t join pg_class c on c.oid = t.tgrelid join pg_namespace n on n.oid = c.relnamespace
  where not t.tgisinternal and n.nspname in ('public', 'f360', 'f360_board')
  union all
  select 'constraint', co.conrelid::regclass::text || '.' || co.conname, md5(pg_get_constraintdef(co.oid))
  from pg_constraint co join pg_namespace n on n.oid = co.connamespace
  where n.nspname in ('public', 'f360', 'f360_board') and co.conrelid <> 0
  union all
  select 'index', n.nspname || '.' || ci.relname, md5(pg_get_indexdef(i.indexrelid))
  from pg_index i join pg_class ci on ci.oid = i.indexrelid join pg_namespace n on n.oid = ci.relnamespace
  where n.nspname in ('public', 'f360', 'f360_board')
  union all
  select 'policy', schemaname || '.' || tablename || '.' || policyname,
         md5(coalesce(cmd, '') || coalesce(roles::text, '') || coalesce(qual, '') || coalesce(with_check, '') || permissive)
  from pg_policies where schemaname in ('public', 'f360', 'f360_board')
  union all
  select 'rls', n.nspname || '.' || c.relname, c.relrowsecurity::text
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname in ('public', 'f360', 'f360_board') and c.relkind in ('r', 'p')
  union all
  select 'table_acl', n.nspname || '.' || c.relname,
         md5(coalesce((select string_agg(x, ',' order by x) from unnest(c.relacl::text[]) x where x !~ '^(postgres|supabase_admin)='), ''))
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname in ('public', 'f360', 'f360_board') and c.relkind in ('r', 'p', 'v', 'm')
  union all
  select 'schema_acl', nspname, md5(coalesce(nspacl::text, '')) from pg_namespace where nspname in ('public', 'f360', 'f360_board')
  union all
  select 'cron', jobname, md5(schedule || '|' || command || '|' || active::text) from cron.job
  union all
  select 'vault_secret_name', name, '' from vault.secrets
  union all
  select 'migration', version, coalesce(name, '') from supabase_migrations.schema_migrations where version >= '20260901'
) z
