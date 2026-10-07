-- Rollback of 20261012001000_f360_publish_yield (deploy the previous publisher first: it never calls this function).
DROP FUNCTION IF EXISTS public.f360_pub_yield(uuid);
