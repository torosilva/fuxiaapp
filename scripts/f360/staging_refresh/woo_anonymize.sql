-- Fuxia 360 · anonimiza la copia de la tienda real en STAGING4 (lo corre woo_refresh.sh; {P} = prefijo de tablas).
-- Clientas = usuarias sin rol administrator/shop_manager. El equipo (administradoras) se conserva.
-- Valores serializados de PHP (a:/O:/s:) que contengan un correo se BORRAN (editar su largo los corrompe); los demás se reemplazan.
-- woo_refresh.sh verifica después que no quede ningún correo de clienta real; si queda, restaura el respaldo de staging4.

CREATE TEMPORARY TABLE f360_cust (ID BIGINT UNSIGNED PRIMARY KEY);
INSERT INTO f360_cust
  SELECT u.ID FROM {P}users u
   WHERE NOT EXISTS (SELECT 1 FROM {P}usermeta m WHERE m.user_id = u.ID AND m.meta_key = '{P}capabilities'
                       AND (m.meta_value LIKE '%administrator%' OR m.meta_value LIKE '%shop_manager%'));

-- ── Usuarias ─────────────────────────────────────────────────────────────────────────────────────────────
UPDATE {P}users u JOIN f360_cust c ON c.ID = u.ID SET
  u.user_email = CONCAT('clienta', u.ID, '@staging.invalid'), u.user_login = CONCAT('clienta', u.ID),
  u.user_nicename = CONCAT('clienta-', u.ID), u.display_name = CONCAT('Clienta ', u.ID),
  u.user_pass = '', u.user_url = '', u.user_activation_key = '';

UPDATE {P}usermeta m JOIN f360_cust c ON c.ID = m.user_id SET m.meta_value = CASE
    WHEN m.meta_key IN ('first_name', 'nickname', 'billing_first_name', 'shipping_first_name') THEN 'Clienta'
    WHEN m.meta_key IN ('last_name', 'billing_last_name', 'shipping_last_name') THEN CAST(m.user_id AS CHAR)
    WHEN m.meta_key = 'billing_email' THEN CONCAT('clienta', m.user_id, '@staging.invalid')
    WHEN m.meta_key IN ('billing_phone', 'shipping_phone') THEN '+15550190000'
    WHEN m.meta_key IN ('billing_address_1', 'shipping_address_1') THEN 'Calle de prueba 123'
    ELSE '' END
 WHERE m.meta_key IN ('first_name', 'nickname', 'last_name', 'description',
                      'billing_first_name', 'billing_last_name', 'billing_email', 'billing_phone', 'billing_company',
                      'billing_address_1', 'billing_address_2',
                      'shipping_first_name', 'shipping_last_name', 'shipping_phone', 'shipping_company',
                      'shipping_address_1', 'shipping_address_2');

DELETE m FROM {P}usermeta m JOIN f360_cust c ON c.ID = m.user_id
 WHERE m.meta_key IN ('session_tokens', 'wc_last_active') OR m.meta_key LIKE '\_woocommerce\_persistent\_cart%'
    OR (m.meta_value REGEXP '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}' AND m.meta_value REGEXP '^[aOs]:[0-9]+:');
UPDATE {P}usermeta m JOIN f360_cust c ON c.ID = m.user_id
   SET m.meta_value = REGEXP_REPLACE(m.meta_value, '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}', 'clienta@staging.invalid')
 WHERE m.meta_value REGEXP '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}' AND m.meta_value NOT LIKE '%@staging.invalid%';

-- ── Pedidos (HPOS) ───────────────────────────────────────────────────────────────────────────────────────
UPDATE {P}wc_orders SET billing_email = CONCAT('pedido', id, '@staging.invalid'), ip_address = '127.0.0.1',
                        user_agent = '', customer_note = '';
UPDATE {P}wc_order_addresses SET first_name = 'Clienta', last_name = CAST(order_id AS CHAR), company = '',
                                 address_1 = 'Calle de prueba 123', address_2 = '', phone = '+15550190000',
                                 email = CONCAT('pedido', order_id, '@staging.invalid');

DELETE FROM {P}wc_orders_meta
 WHERE meta_value REGEXP '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}' AND meta_value REGEXP '^[aOs]:[0-9]+:';
UPDATE {P}wc_orders_meta
   SET meta_value = REGEXP_REPLACE(meta_value, '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}', 'pedido@staging.invalid')
 WHERE meta_value REGEXP '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}' AND meta_value NOT LIKE '%@staging.invalid%';
UPDATE {P}wc_orders_meta SET meta_value = '+15550190000'
 WHERE meta_key LIKE '%phone%' AND meta_value <> '' AND meta_value NOT REGEXP '^[aOs]:[0-9]+:';
UPDATE {P}wc_orders_meta SET meta_value = '127.0.0.1' WHERE meta_key IN ('_customer_ip_address', 'is_vat_exempt_ip');

-- Copias "legacy" de pedidos en posts/postmeta (sincronización HPOS) y notas de pedido.
CREATE TEMPORARY TABLE f360_order_posts (ID BIGINT UNSIGNED PRIMARY KEY);
INSERT INTO f360_order_posts SELECT ID FROM {P}posts WHERE post_type IN ('shop_order', 'shop_order_refund', 'shop_order_placehold');
DELETE pm FROM {P}postmeta pm JOIN f360_order_posts o ON o.ID = pm.post_id
 WHERE pm.meta_value REGEXP '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}' AND pm.meta_value REGEXP '^[aOs]:[0-9]+:';
UPDATE {P}postmeta pm JOIN f360_order_posts o ON o.ID = pm.post_id SET pm.meta_value = CASE
    WHEN pm.meta_key LIKE '%\_email' THEN CONCAT('pedido', pm.post_id, '@staging.invalid')
    WHEN pm.meta_key LIKE '%phone%' THEN '+15550190000'
    WHEN pm.meta_key LIKE '%first\_name' THEN 'Clienta'
    WHEN pm.meta_key LIKE '%last\_name' THEN CAST(pm.post_id AS CHAR)
    WHEN pm.meta_key LIKE '%address\_1' THEN 'Calle de prueba 123'
    WHEN pm.meta_key LIKE '%address\_2' OR pm.meta_key LIKE '%company' THEN ''
    WHEN pm.meta_key = '_customer_ip_address' THEN '127.0.0.1'
    ELSE REGEXP_REPLACE(pm.meta_value, '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}', 'pedido@staging.invalid') END
 WHERE pm.meta_key REGEXP '(email|phone|first_name|last_name|address_1|address_2|company|_customer_ip_address)$'
    OR pm.meta_value REGEXP '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}';
UPDATE {P}comments SET comment_content = REGEXP_REPLACE(comment_content, '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}', 'pedido@staging.invalid'),
                       comment_author_IP = '127.0.0.1'
 WHERE comment_type = 'order_note';

-- ── Reseñas (el nombre ya es público en la tienda; el correo y la IP no) ─────────────────────────────────
UPDATE {P}comments SET comment_author_email = CONCAT('resena', comment_ID, '@staging.invalid'),
                       comment_author_IP = '127.0.0.1', comment_agent = ''
 WHERE comment_author_email <> '' AND comment_author_email NOT LIKE '%@fuxiaballerinas.com' AND comment_type <> 'order_note';

-- ── Índice de clientas de WooCommerce ────────────────────────────────────────────────────────────────────
UPDATE {P}wc_customer_lookup SET email = CONCAT('clienta', customer_id, '@staging.invalid'), first_name = 'Clienta',
                                 last_name = CAST(customer_id AS CHAR), username = CONCAT('clienta', customer_id);

-- ── Datos que no se copian: leads, avisos, carritos, sesiones, tokens de pago, registros ─────────────────
-- DELETE (no TRUNCATE): algunas tablas tienen llaves foráneas entre sí; primero las hijas, luego las madres.
DELETE FROM {P}fuxia_leads;
DELETE FROM {P}wc_stock_notificationmeta;
DELETE FROM {P}wc_stock_notifications;
DELETE FROM {P}cartflows_ca_email_history;
DELETE FROM {P}cartflows_ca_cart_abandonment;
DELETE FROM {P}cr_reminders_log;
DELETE FROM {P}epayco_order;
DELETE FROM {P}social_users;
DELETE FROM {P}woocommerce_sessions;
DELETE FROM {P}woocommerce_payment_tokenmeta;
DELETE FROM {P}woocommerce_payment_tokens;
DELETE FROM {P}woocommerce_log;
DELETE FROM {P}wpmailsmtp_debug_events;
DELETE FROM {P}wpmailsmtp_tasks_meta;
DELETE FROM {P}actionscheduler_logs;
DELETE FROM {P}sgs_log_events;
DELETE FROM {P}sgs_log_visitors;
DELETE FROM {P}sg_ai_log_events;
DELETE FROM {P}clarity_collect_events;
DELETE FROM {P}wc_download_log;
DELETE FROM {P}wc_rate_limits;
DELETE FROM {P}wc_reserved_stock;
-- Tareas programadas pendientes de prod (correos, sincronizaciones con Google/Meta): no corren en staging4.
DELETE FROM {P}actionscheduler_actions WHERE status IN ('pending', 'in-progress');
