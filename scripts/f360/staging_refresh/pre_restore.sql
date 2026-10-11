-- Fuxia 360 · Copia PROD → STAGING · paso 1 de 3 (corre EN STAGING, dentro de la transacción única de refresh.sh).
-- Guarda lo que es propio de staging (configuración de ambiente y usuarios demo) en tablas temporales,
-- y vacía los esquemas de la app para recibir el esquema y los datos de producción.
-- NO toca: vault (secretos y URLs de staging), cron (tareas de staging), storage (archivos), realtime, net.

-- Barrera: este archivo solo puede correr en staging.
do $$
begin
  if current_setting('fuxia.target_ref', true) is distinct from 'faltxpkaicwpnlqaxrdu' then
    raise exception 'ABORT: pre_restore.sql solo corre en staging (faltx…)';
  end if;
end $$;

-- ── 1. Lo que staging conserva ─────────────────────────────────────────────────────────────────────────
-- Destinos de venta: staging apunta a la tienda staging4; producción a la tienda real. Nunca se copian los de prod.
create temp table keep_sales_targets on commit drop as select * from f360.sales_targets;
-- Correos que reciben avisos internos en staging.
create temp table keep_notification_recipients on commit drop as select * from f360.notification_recipients;
-- Usuarios propios de staging (demo y pruebas): correos @staging.invalid o con rol en el admin de staging.
create temp table keep_users on commit drop as
  select u.* from auth.users u
   where u.email like '%@staging.invalid'
      or u.id in (select auth_user_id from f360.user_roles);
create temp table keep_identities on commit drop as
  select i.* from auth.identities i where i.user_id in (select id from keep_users);
create temp table keep_user_roles on commit drop as
  select r.* from f360.user_roles r where r.auth_user_id in (select id from keep_users);

-- ── 2. Vaciar los esquemas de la app ───────────────────────────────────────────────────────────────────
drop schema if exists f360_board cascade;
drop schema if exists f360 cascade;

-- public no se borra (Supabase le da permisos por defecto que no podemos recrear); se vacía objeto por objeto.
do $$
declare r record;
begin
  for r in
    select c.oid::regclass::text as n, c.relkind
      from pg_class c join pg_namespace s on s.oid = c.relnamespace
     where s.nspname = 'public' and c.relkind in ('v','m','f','p','r','S')
       and not exists (select 1 from pg_depend d where d.classid = 'pg_class'::regclass and d.objid = c.oid and d.deptype = 'e')
     order by case c.relkind when 'v' then 1 when 'm' then 2 when 'f' then 3 when 'p' then 4 when 'r' then 5 else 6 end
  loop
    if to_regclass(r.n) is null then continue; end if;          -- ya cayó por cascada
    execute format('drop %s if exists %s cascade',
      case r.relkind when 'v' then 'view' when 'm' then 'materialized view' when 'f' then 'foreign table'
                     when 'S' then 'sequence' else 'table' end, r.n);
  end loop;

  for r in
    select p.oid::regprocedure::text as sig, p.prokind
      from pg_proc p join pg_namespace s on s.oid = p.pronamespace
     where s.nspname = 'public'
       and not exists (select 1 from pg_depend d where d.classid = 'pg_proc'::regclass and d.objid = p.oid and d.deptype = 'e')
  loop
    execute format('drop %s if exists %s cascade',
      case r.prokind when 'p' then 'procedure' when 'a' then 'aggregate' else 'function' end, r.sig);
  end loop;

  for r in
    select t.oid, t.typtype
      from pg_type t join pg_namespace s on s.oid = t.typnamespace
     where s.nspname = 'public' and t.typtype in ('e','c','d','r')
       and (t.typtype <> 'c' or exists (select 1 from pg_class c where c.oid = t.typrelid and c.relkind = 'c'))
       and not exists (select 1 from pg_depend d where d.classid = 'pg_type'::regclass and d.objid = t.oid and d.deptype = 'e')
  loop
    if not exists (select 1 from pg_type where oid = r.oid) then continue; end if;
    execute format('drop %s if exists %s cascade', case r.typtype when 'd' then 'domain' else 'type' end, r.oid::regtype::text);
  end loop;
end $$;

-- Usuarios de Auth y la historia de migraciones se reemplazan por los de producción.
truncate auth.users cascade;
truncate supabase_migrations.schema_migrations;

-- Las políticas de archivos (storage) se reemplazan por las de producción (prod_storage_policies.sql).
do $$
declare r record;
begin
  for r in select policyname from pg_policies where schemaname = 'storage' and tablename = 'objects' loop
    execute format('drop policy if exists %I on storage.objects', r.policyname);
  end loop;
end $$;
