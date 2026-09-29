-- GEAEMS Portal v0.3
-- Make profile activation state authoritative for administrative access.
-- Run after 001 and 002.

begin;

create or replace function private.is_user_active()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.profiles p
    where p.id = (select auth.uid())
      and p.active = true
  );
$$;

create or replace function private.is_system_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.is_user_active()
    and exists (
      select 1
      from public.user_roles ur
      where ur.user_id = (select auth.uid())
        and ur.role = 'system_admin'
    );
$$;

create or replace function private.has_agency_access(p_agency_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.is_user_active()
    and (
      private.is_system_admin()
      or exists (
        select 1
        from public.user_agency_access uaa
        where uaa.user_id = (select auth.uid())
          and uaa.agency_id = p_agency_id
      )
    );
$$;

revoke execute on function private.is_user_active() from public, anon;
revoke execute on function private.is_system_admin() from public, anon;
revoke execute on function private.has_agency_access(uuid) from public, anon;
grant execute on function private.is_user_active() to authenticated;
grant execute on function private.is_system_admin() to authenticated;
grant execute on function private.has_agency_access(uuid) to authenticated;

commit;

NOTIFY pgrst, 'reload schema';
