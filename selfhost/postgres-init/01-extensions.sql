-- Runs only on a data directory created from nothing, which is why it is not the authority for
-- extensions: an instance that already exists never sees a line added here. The db-init service in
-- docker-compose.yml creates the same set on every boot and is what an existing instance gets.
-- Keep the two lists the same.
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS ltree;
CREATE EXTENSION IF NOT EXISTS pgcrypto;
-- module-inventory's custody exclusion constraint is `exclude using gist (asset_id with =, ...)`,
-- and a uuid has no default gist operator class without this. Missing here until 2026-08-28, which
-- meant the module's own migration threw on any clean database — and a module migration that
-- throws takes down every module in its host service, so core never bound :4000.
CREATE EXTENSION IF NOT EXISTS btree_gist;
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
