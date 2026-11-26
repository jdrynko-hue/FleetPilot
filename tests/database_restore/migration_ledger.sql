SELECT count(*),
       count(*) FILTER (WHERE migration.version = :'recovery_version') = 1,
       encode(sha256(convert_to(
         coalesce(jsonb_agg(to_jsonb(migration) ORDER BY migration.version COLLATE "C")::text, '[]'),
         'UTF8')), 'hex')
FROM supabase_migrations.schema_migrations AS migration;
