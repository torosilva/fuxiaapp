# Exposición — 2026-10-11 (staging)

> Sin valores secretos en este documento.

- **Qué:** al diagnosticar una sesión que bloqueaba staging, Claude ejecutó `ps aux`. La línea de comando de un `psql` de otra sesión (refresh de staging, ensayo) contenía la URL de Postgres de **STAGING** (`faltx…`) con su contraseña, y se imprimió en la conversación.
- **Dónde quedó:** solo en la transcripción local de esta sesión y en la conversación con el modelo. No está en git, en archivos del repo ni en logs.
- **Riesgo:** medio-bajo. Es la base de staging, pero contiene el catálogo real de Carolina y datos de prueba.
- **Recomendación:** rotar la contraseña de la base de staging en el panel de Supabase (Database → Settings → Reset database password) y actualizar `~/.fuxia-staging.env` (`STAGING_DB_URL`).
- **Causa de fondo:** los scripts pasan la URL con contraseña como argumento de `psql`, y queda visible en la lista de procesos. **Mejora:** usar `PGPASSWORD` o `~/.pgpass` en lugar de ponerla en la URL. **Regla para Claude:** nunca listar procesos sin enmascarar (`sed -E 's#(postgres(ql)?://[^:]+:)[^@]+@#\1***@#g'`).
