-- Fuxia 360 · Copia PROD → STAGING · paso 3 de 3 (corre EN STAGING, misma transacción, después de cargar prod).
-- 1) anonimiza a las clientas, 2) apaga todo lo que podría escribirle a alguien real o a la tienda real,
-- 3) devuelve a staging su configuración propia, 4) VERIFICA que no quedó ningún dato personal de prod.
-- Si la verificación encuentra algo, la transacción entera se deshace y staging queda como estaba.
-- Las internas (equipo con rol en el admin, vendedoras, junta) se conservan tal cual para poder entrar a staging.

do $$
begin
  if current_setting('fuxia.target_ref', true) is distinct from 'faltxpkaicwpnlqaxrdu' then
    raise exception 'ABORT: post_restore.sql solo corre en staging (faltx…)';
  end if;
end $$;

-- Los triggers de la app no deben dispararse aquí (algunos auditan cambios y copiarían el dato original).
set session_replication_role = replica;

-- ── 0. Utilidades ──────────────────────────────────────────────────────────────────────────────────────
create or replace function pg_temp.digits(v text) returns text language sql immutable as
  $f$ select right(regexp_replace(coalesce(v, ''), '\D', '', 'g'), 10) $f$;

-- Copia filas entre tablas usando solo las columnas que ambas tienen (el esquema de staging y el de prod pueden diferir).
create or replace function pg_temp.copy_rows(src regclass, dst regclass, where_sql text default 'true', tail text default '')
returns bigint language plpgsql as $f$
declare cols text; n bigint;
begin
  select string_agg(quote_ident(a.attname), ', ' order by a.attnum) into cols
    from pg_attribute a
   where a.attrelid = dst and a.attnum > 0 and not a.attisdropped and a.attgenerated = ''
     and exists (select 1 from pg_attribute b where b.attrelid = src and b.attname = a.attname and b.attnum > 0 and not b.attisdropped);
  execute format('insert into %s (%s) overriding system value select %s from %s s where %s %s', dst, cols, cols, src, where_sql, tail);
  get diagnostics n = row_count;
  return n;
end $f$;

-- ── 1. Quién es interno ────────────────────────────────────────────────────────────────────────────────
create temp table internal_users on commit drop as
  select auth_user_id as id from f360.user_roles
  union select auth_user_id from f360.sellers where auth_user_id is not null
  union select auth_user_id from f360_board.board_members where auth_user_id is not null
  union select auth_user_id from f360.location_assignments
  union select auth_user_id from f360.customer_pii_viewers
  union select auth_user_id from public.customers where role in ('staff', 'admin') and auth_user_id is not null;

create temp table internal_customers on commit drop as
  select id from public.customers
   where role in ('staff', 'admin') or auth_user_id in (select id from internal_users)
  union select customer_id from f360.sellers where customer_id is not null;

create temp table internal_keys on commit drop as
  select pg_temp.digits(phone) as k from auth.users where id in (select id from internal_users) and phone is not null
  union select pg_temp.digits(phone) from public.customers where id in (select id from internal_customers)
  union select pg_temp.digits(phone) from f360.sellers
  union select pg_temp.digits(phone) from f360.weekly_people
  union select lower(email) from auth.users where id in (select id from internal_users) and email is not null
  union select lower(email) from public.customers where id in (select id from internal_customers) and email is not null;
delete from internal_keys where k is null or k = '';

-- ── 2. Inventario de datos personales (antes de tocarlos: con esto se verifica al final) ───────────────
create temp table pii_cols (tbl text, col text, kind text) on commit drop;
insert into pii_cols values
  ('public.customers', 'phone', 'phone'), ('public.customers', 'email', 'email'), ('public.customers', 'name', 'name'),
  ('auth.users', 'phone', 'phone'), ('auth.users', 'email', 'email'),
  ('public.offline_sales', 'customer_phone', 'phone'),
  ('public.pending_credits', 'phone', 'phone'), ('public.pending_credits', 'email', 'email'),
  ('public.unmatched_orders', 'phone', 'phone'), ('public.unmatched_orders', 'email', 'email'),
  ('public.referrals', 'referred_phone', 'phone'), ('public.referrals', 'referred_email', 'email'),
  ('public.support_tickets', 'customer_phone', 'phone'), ('public.support_tickets', 'customer_name', 'name'),
  ('f360.custom_requests', 'phone', 'phone'), ('f360.custom_requests', 'customer_name', 'name'),
  ('f360.customer_cases', 'phone', 'phone'), ('f360.customer_cases', 'email', 'email'), ('f360.customer_cases', 'customer_name', 'name'),
  ('f360.customer_verifications', 'phone', 'phone'),
  ('f360.order_shipping', 'phone', 'phone'), ('f360.order_shipping', 'email', 'email'), ('f360.order_shipping', 'name', 'name'),
  ('f360.reserve_codes', 'phone', 'phone'),
  ('f360.stock_intents', 'contact_phone', 'phone'), ('f360.stock_intents', 'contact_name', 'name');

-- Solo columnas que existen en el esquema de prod de hoy.
delete from pii_cols p where not exists (
  select 1 from information_schema.columns c
   where c.table_schema = split_part(p.tbl, '.', 1) and c.table_name = split_part(p.tbl, '.', 2) and c.column_name = p.col);

create temp table pii_values (kind text, v text) on commit drop;
do $$
declare r record;
begin
  for r in select * from pii_cols loop
    execute format('insert into pii_values select %L, %I::text from %s where %I is not null', r.kind, r.col, r.tbl, r.col);
  end loop;
end $$;

-- Agujas para la verificación final: teléfono (10 dígitos), correo, nombre completo (con espacio, 8+ letras).
create temp table pii_needles on commit drop as
  select distinct 'teléfono' as kind, pg_temp.digits(v) as n from pii_values where kind = 'phone' and length(pg_temp.digits(v)) >= 7
  union select distinct 'correo', lower(v) from pii_values where kind = 'email' and v like '%@%'
  union select distinct 'nombre', lower(btrim(v)) from pii_values where kind = 'name' and btrim(v) like '% %' and length(btrim(v)) >= 8;
delete from pii_needles where n in (select k from internal_keys);

-- Nombres del equipo: no son agujas aunque una clienta se llame igual. Incluye los nombres que aparecen en las
-- columnas de auditoría (quién hizo qué: *_by_name, actor_name, *_by, ...), que por definición son del equipo.
create temp table internal_names (n text) on commit drop;
insert into internal_names
  select lower(btrim(name)) from public.customers where id in (select id from internal_customers) and name is not null
  union select lower(btrim(name)) from f360.sellers where name is not null
  union select lower(btrim(name)) from f360.weekly_people where name is not null
  union select lower(btrim(name)) from public.staff where name is not null
  union select lower(btrim(display_name)) from f360.user_roles where display_name is not null
  union select lower(btrim(coalesce(raw_user_meta_data ->> 'display_name', raw_user_meta_data ->> 'full_name', raw_user_meta_data ->> 'name')))
          from auth.users where id in (select id from internal_users);
do $$
declare r record;
begin
  for r in
    select c.table_schema as s, c.table_name as t, c.column_name as col
      from information_schema.columns c
      join information_schema.tables tb on tb.table_schema = c.table_schema and tb.table_name = c.table_name and tb.table_type = 'BASE TABLE'
     where c.table_schema in ('public', 'f360', 'f360_board') and c.data_type in ('text', 'character varying')
       and (c.column_name ~ '(_by_name|_by|^actor_name|^by_name|^set_by_name|^granted_by_name|^revoked_by_name)$')
  loop
    execute format('insert into pg_temp.internal_names select distinct lower(btrim(%I)) from %I.%I where %I is not null', r.col, r.s, r.t, r.col);
  end loop;
end $$;
delete from pii_needles where kind = 'nombre' and n in (select n from internal_names where n is not null);

-- ── 3. Mapas de reemplazo, estables dentro de esta copia ───────────────────────────────────────────────
-- Teléfonos ficticios +1 555 019 NNNN (el laboratorio de staging usa +1 555 010 NNNN; no se cruzan).
create temp table phone_map on commit drop as
  select k, '+1555019' || lpad(row_number() over (order by k)::text, 4, '0') as fake
    from (select distinct pg_temp.digits(v) as k from pii_values where kind = 'phone') x
   where length(k) >= 7 and k not in (select k from internal_keys);
do $$ begin if (select count(*) from phone_map) > 9999 then raise exception 'ABORT: más de 9999 teléfonos'; end if; end $$;

-- Correos: los de inicio de sesión por teléfono (<telefono>@fuxia.app) siguen al teléfono; el resto, ficticios.
create temp table email_map on commit drop as
  select e, case
           when e ~ '^\+?\d{7,15}@fuxia\.app$' and pm.fake is not null then regexp_replace(pm.fake, '\D', '', 'g') || '@fuxia.app'
           else 'clienta' || row_number() over (order by e) || '@staging.invalid'
         end as fake
    from (select distinct lower(v) as e from pii_values where kind = 'email' and v like '%@%') x
    left join phone_map pm on pm.k = pg_temp.digits(split_part(x.e, '@', 1))
   where e not in (select k from internal_keys);

-- ── 4. Anonimizar ──────────────────────────────────────────────────────────────────────────────────────
do $$
declare r record;
begin
  for r in select * from pii_cols where kind = 'phone' and tbl <> 'auth.users' loop
    execute format('update %s t set %I = m.fake from pg_temp.phone_map m where pg_temp.digits(t.%I) = m.k', r.tbl, r.col, r.col);
  end loop;
  for r in select * from pii_cols where kind = 'email' and tbl <> 'auth.users' loop
    execute format('update %s t set %I = m.fake from pg_temp.email_map m where lower(t.%I) = m.e', r.tbl, r.col, r.col);
  end loop;
  for r in select * from pii_cols where kind = 'name' and tbl <> 'public.customers' loop
    execute format('update %s set %I = %L where %I is not null', r.tbl, r.col, 'Clienta anónima', r.col);
  end loop;
end $$;

-- Clientas: nombre "Clienta N", dirección de prueba, cumpleaños con el mismo día y mes (año 2000), sin foto.
with n as (select id, row_number() over (order by created_at, id) as i from public.customers
            where id not in (select id from internal_customers))
update public.customers c set
  name = 'Clienta ' || n.i,
  address_street = case when c.address_street is not null then 'Calle de prueba ' || n.i end,
  address_neighborhood = case when c.address_neighborhood is not null then 'Colonia Prueba' end,
  birthday = case when c.birthday is not null
                  then make_date(2000, extract(month from c.birthday)::int, extract(day from c.birthday)::int) end,
  avatar_url = null
from n where n.id = c.id;

-- Cuentas de Auth de clientas.
update auth.users u set
  phone = coalesce((select regexp_replace(m.fake, '\D', '', 'g') from pg_temp.phone_map m where m.k = pg_temp.digits(u.phone)),
                   case when u.phone is null then null end),
  email = coalesce((select m.fake from pg_temp.email_map m where m.e = lower(u.email)),
                   case when u.email is null then null end),
  raw_user_meta_data = jsonb_strip_nulls(jsonb_build_object(
    'sub', u.raw_user_meta_data ->> 'sub',
    'email_verified', u.raw_user_meta_data -> 'email_verified',
    'phone_verified', u.raw_user_meta_data -> 'phone_verified'))
where u.id not in (select id from internal_users);

update auth.identities i set
  identity_data = jsonb_strip_nulls(jsonb_build_object(
    'sub', i.identity_data ->> 'sub',
    'email', u.email,
    'phone', u.phone,
    'email_verified', i.identity_data -> 'email_verified',
    'phone_verified', i.identity_data -> 'phone_verified')),
  provider_id = case when i.provider_id like '%@%' then coalesce(u.email, i.user_id::text)
                     when i.provider_id ~ '^\+?\d{7,15}$' then coalesce(u.phone, i.user_id::text)
                     else i.provider_id end
from auth.users u
where u.id = i.user_id and i.user_id not in (select id from internal_users);

-- Textos libres escritos por o sobre clientas.
update f360.customer_cases set transcript = '[]'::jsonb where transcript is not null;
update f360.customer_cases set summary = 'Caso anonimizado' where summary is not null;
update f360.custom_requests set note = null where note is not null;
update public.support_tickets set last_messages = '[]'::jsonb, notes = null;
update f360.customer_consent_events set evidence = jsonb_build_object('anonimizado', true) where evidence is not null;
update f360.customer_consent_events set actor = actor - 'phone' - 'email' - 'name' where actor is not null;

-- Claves que llevan el teléfono adentro (p. ej. pending_credits.idem_key): se cambia solo el teléfono.
update public.pending_credits p set idem_key = replace(p.idem_key, m.k, right(regexp_replace(m.fake, '\D', '', 'g'), 10))
  from pg_temp.phone_map m where p.idem_key like '%' || m.k || '%';

-- Motivos escritos a mano: si mencionan a una clienta, se reemplaza el texto.
update f360.sale_channel_overrides o set reason = 'Motivo anonimizado'
 where exists (select 1 from pg_temp.pii_needles n where lower(o.reason) like '%' || n.n || '%');

-- ── 5. URLs del proyecto de prod → proyecto de staging (fotos, enlaces guardados en datos) ─────────────
do $$
declare r record;
begin
  for r in
    select c.table_schema as s, c.table_name as t, c.column_name as col, c.data_type as dt
      from information_schema.columns c
      join information_schema.tables tb on tb.table_schema = c.table_schema and tb.table_name = c.table_name and tb.table_type = 'BASE TABLE'
     where c.table_schema in ('public', 'f360', 'f360_board') and c.data_type in ('text', 'character varying', 'jsonb')
       and c.is_generated = 'NEVER'
  loop
    execute format('update %I.%I set %I = replace(%I::text, %L, %L)::%s where %I::text like %L',
      r.s, r.t, r.col, r.col, 'tgzgiwfzddsghnxgkcqd', 'faltxpkaicwpnlqaxrdu',
      case r.dt when 'jsonb' then 'jsonb' else 'text' end, r.col, '%tgzgiwfzddsghnxgkcqd%');
  end loop;
end $$;

-- ── 6. Configuración propia de staging ─────────────────────────────────────────────────────────────────
-- Si esa misma noche staging4 se copió de la tienda real (woo_refresh.sh), los IDs de producto de staging4 = los de prod.
-- Entonces el destino de prod (con todos sus vínculos, pedidos y reseñas) pasa a llamarse woo_staging4, que es la clave que
-- usan las funciones de staging (WOO_TARGET_KEY / F360_STOREFRONT_TARGET), y recibe la configuración de staging4 abajo.
-- Las relaciones van por id (FK a sales_targets.id), así que cambiar la clave no rompe nada.
do $$
begin
  if current_setting('fuxia.woo_mirrored', true) = 'on'
     and exists (select 1 from f360.sales_targets where key = 'woo_production') then
    update f360.sales_targets set key = 'woo_staging4_anterior' where key = 'woo_staging4';
    update f360.sales_targets set key = 'woo_staging4' where key = 'woo_production';
    raise notice 'Woo copiada esta noche: el destino de producción quedó como woo_staging4 (IDs de prod = IDs de staging4).';
  end if;
end $$;

-- Destinos de prod que staging no tiene: apagados y sin URL real.
update f360.sales_targets set
  active = false, orders_mode = 'off', catalog_mode = 'off', stock_sync_mode = 'off', storefront_enabled = false,
  base_url = 'https://' || replace(key, '_', '-') || '.staging.invalid'
where key not in (select key from pg_temp.keep_sales_targets);

-- Destinos que staging sí tiene: vuelven a su configuración de staging.
do $$
declare cols text;
begin
  select string_agg(format('%I = k.%I', a.attname, a.attname), ', ') into cols
    from pg_attribute a
   where a.attrelid = 'f360.sales_targets'::regclass and a.attnum > 0 and not a.attisdropped and a.attgenerated = ''
     and a.attname not in ('id', 'key', 'created_at')
     -- Con Woo copiada, el cursor de pedidos de prod sigue valiendo (staging4 tiene los mismos pedidos).
     and not (a.attname = 'orders_since_id' and current_setting('fuxia.woo_mirrored', true) = 'on')
     and exists (select 1 from pg_attribute b where b.attrelid = 'pg_temp.keep_sales_targets'::regclass
                  and b.attname = a.attname and b.attnum > 0 and not b.attisdropped);
  execute format('update f360.sales_targets t set %s from pg_temp.keep_sales_targets k where k.key = t.key', cols);
end $$;
select pg_temp.copy_rows('pg_temp.keep_sales_targets', 'f360.sales_targets',
  'not exists (select 1 from f360.sales_targets t where t.key = s.key or t.id = s.id)');

delete from f360.notification_recipients;
select pg_temp.copy_rows('pg_temp.keep_notification_recipients', 'f360.notification_recipients');

-- Usuarios demo/pruebas de staging (si su correo no choca con uno de prod).
create temp table restored_users on commit drop as
  select k.id from pg_temp.keep_users k
   where not exists (select 1 from auth.users u where u.id = k.id or lower(u.email) = lower(k.email));
select pg_temp.copy_rows('pg_temp.keep_users', 'auth.users', 'id in (select id from pg_temp.restored_users)');
select pg_temp.copy_rows('pg_temp.keep_identities', 'auth.identities',
  'user_id in (select id from pg_temp.restored_users) and not exists (select 1 from auth.identities i where i.id = s.id or (i.provider = s.provider and i.provider_id = s.provider_id))');
select pg_temp.copy_rows('pg_temp.keep_user_roles', 'f360.user_roles',
  'auth_user_id in (select id from pg_temp.restored_users)', 'on conflict do nothing');

set session_replication_role = origin;

-- ── 7. Verificación: ningún dato personal de una clienta de prod puede quedar en staging ───────────────
do $$
declare r record; hits bigint; kinds text; report text := '';
begin
  for r in
    select c.table_schema as s, c.table_name as t, c.column_name as col
      from information_schema.columns c
      join information_schema.tables tb on tb.table_schema = c.table_schema and tb.table_name = c.table_name and tb.table_type = 'BASE TABLE'
     where (c.table_schema in ('public', 'f360', 'f360_board')
            or (c.table_schema = 'auth' and c.table_name in ('users', 'identities')))
       and c.data_type in ('text', 'character varying', 'jsonb', 'json', 'ARRAY')
  loop
    execute format('select count(*), string_agg(distinct n.kind, '', '') from %I.%I x join pg_temp.pii_needles n on lower(x.%I::text) like ''%%'' || n.n || ''%%''',
                   r.s, r.t, r.col) into hits, kinds;
    if hits > 0 then report := report || format(E'\n  %s.%s.%s: %s coincidencia(s) de %s de clienta', r.s, r.t, r.col, hits, kinds); end if;
    -- Segunda red: cualquier correo que no sea ficticio, interno o de la empresa (p. ej. de un pedido de Woo guardado en un log).
    execute format($q$
      select count(*) from (
        select lower(m[1]) as e from %I.%I x, regexp_matches(x.%I::text, '([A-Za-z0-9._%%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,})', 'g') m
      ) f
      where split_part(f.e, '@', 2) not in ('staging.invalid', 'fuxia.app', 'fuxiaballerinas.com', 'example.com')
        and f.e not in (select k from pg_temp.internal_keys)
        and f.e not in (select lower(email) from f360.notification_recipients where email is not null)
        and f.e not in (select lower(email) from pg_temp.keep_users where email is not null)$q$,
      r.s, r.t, r.col) into hits;
    if hits > 0 then report := report || format(E'\n  %s.%s.%s: %s correo(s) no anonimizado(s)', r.s, r.t, r.col, hits); end if;
  end loop;
  if report <> '' then
    raise exception 'ABORT: quedaron datos personales de producción en staging (no se aplica nada):%', report;
  end if;
  raise notice 'Verificación OK: % agujas revisadas, ningún dato personal de clientas de prod en staging.',
    (select count(*) from pg_temp.pii_needles);
end $$;

-- Resumen (solo conteos).
select 'clientas' as que, count(*) as n from public.customers where id not in (select id from pg_temp.internal_customers)
union all select 'internas conservadas', count(*) from pg_temp.internal_users
union all select 'usuarios demo de staging restaurados', count(*) from pg_temp.restored_users
union all select 'teléfonos reemplazados', count(*) from pg_temp.phone_map
union all select 'correos reemplazados', count(*) from pg_temp.email_map
union all select 'destinos de venta activos', count(*) from f360.sales_targets where active;
