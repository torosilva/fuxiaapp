-- Baseline (2/2): storage.objects policies exactly as they exist in production
-- (source: schema-only dump of the `storage` schema, 2026-09-24, S0.1a).
--
-- PRODUCTION: never executed. Registered as already-applied via
--   supabase migration repair --status applied 20260924000001 --linked
-- STAGING: executed on an empty project to reproduce production policies.
--
-- Deliberately excluded:
--   * the rest of the storage schema (Supabase-managed; created by the platform)
--   * ALTER TABLE storage.* ENABLE ROW LEVEL SECURITY (platform-managed, already on)
--   * bucket rows (data, not schema). Staging buckets are created by the staging
--     seed script, not by this migration.

DROP POLICY IF EXISTS "Avatars are publicly readable" ON "storage"."objects";
CREATE POLICY "Avatars are publicly readable" ON "storage"."objects" FOR SELECT USING (("bucket_id" = 'avatars'::"text"));

DROP POLICY IF EXISTS "Users can delete their own avatar" ON "storage"."objects";
CREATE POLICY "Users can delete their own avatar" ON "storage"."objects" FOR DELETE USING ((("bucket_id" = 'avatars'::"text") AND (("storage"."foldername"("name"))[1] = ("auth"."uid"())::"text")));

DROP POLICY IF EXISTS "Users can update their own avatar" ON "storage"."objects";
CREATE POLICY "Users can update their own avatar" ON "storage"."objects" FOR UPDATE USING ((("bucket_id" = 'avatars'::"text") AND (("storage"."foldername"("name"))[1] = ("auth"."uid"())::"text")));

DROP POLICY IF EXISTS "Users can upload their own avatar" ON "storage"."objects";
CREATE POLICY "Users can upload their own avatar" ON "storage"."objects" FOR INSERT WITH CHECK ((("bucket_id" = 'avatars'::"text") AND (("storage"."foldername"("name"))[1] = ("auth"."uid"())::"text")));
