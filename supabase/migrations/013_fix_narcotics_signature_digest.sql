-- GEAEMS Portal v0.6.5
-- Fix narcotics electronic-signature hashing.
--
-- The narcotics save/sign RPC is SECURITY DEFINER and intentionally used an
-- empty search_path. pgcrypto is installed in Supabase's `extensions` schema,
-- so the unqualified digest(...) call could not be resolved at runtime.
-- Keep untrusted/public schemas out of the function search path while allowing
-- PostgreSQL built-ins and the trusted extensions schema.

begin;

alter function public.save_narcotics_count(
  uuid,
  uuid,
  date,
  text,
  text,
  text,
  boolean,
  text,
  text,
  jsonb
)
set search_path = pg_catalog, extensions;

notify pgrst, 'reload schema';

commit;
