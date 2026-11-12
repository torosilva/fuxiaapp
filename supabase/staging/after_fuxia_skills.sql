-- Fuxia Skills en staging después de cada copia nocturna (prod aún no tiene la biblioteca): carga idempotente de las 10 skills.
BEGIN;
\ir data_fuxia_skills.sql
COMMIT;
