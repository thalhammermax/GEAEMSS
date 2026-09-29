-- GEAEMS Portal v0.3.6
-- Provider self-service isolation and role-aware agency authorization.
-- Run after 001, 002 and 003.

begin;

-- An agency-access row alone must never elevate a normal provider account.
-- The account must also hold the Agency Administrator role (or be a System Admin).
create or replace function private.is_agency_admin()
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
        and ur.role = 'agency_admin'
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
      or (
        private.is_agency_admin()
        and exists (
          select 1
          from public.user_agency_access uaa
          where uaa.user_id = (select auth.uid())
            and uaa.agency_id = p_agency_id
        )
      )
    );
$$;

create or replace function private.can_manage_agency_personnel(p_agency_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.is_user_active()
    and (
      private.is_system_admin()
      or (
        private.is_agency_admin()
        and exists (
          select 1
          from public.user_agency_access uaa
          where uaa.user_id = (select auth.uid())
            and uaa.agency_id = p_agency_id
            and uaa.can_manage_personnel = true
        )
      )
    );
$$;

create or replace function private.can_manage_agency_credentials(p_agency_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.is_user_active()
    and (
      private.is_system_admin()
      or (
        private.is_agency_admin()
        and exists (
          select 1
          from public.user_agency_access uaa
          where uaa.user_id = (select auth.uid())
            and uaa.agency_id = p_agency_id
            and uaa.can_manage_credentials = true
        )
      )
    );
$$;

create or replace function private.can_view_provider(p_provider_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.is_user_active()
    and (
      private.is_system_admin()
      or private.is_self_provider(p_provider_id)
      or (
        private.is_agency_admin()
        and exists (
          select 1
          from public.provider_agencies pa
          join public.user_agency_access uaa on uaa.agency_id = pa.agency_id
          where pa.provider_id = p_provider_id
            and pa.active = true
            and uaa.user_id = (select auth.uid())
        )
      )
    );
$$;

create or replace function private.can_manage_provider_credentials(p_provider_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.is_user_active()
    and (
      private.is_system_admin()
      or (
        private.is_agency_admin()
        and exists (
          select 1
          from public.provider_agencies pa
          join public.user_agency_access uaa on uaa.agency_id = pa.agency_id
          where pa.provider_id = p_provider_id
            and pa.active = true
            and uaa.user_id = (select auth.uid())
            and uaa.can_manage_credentials = true
        )
      )
    );
$$;

create or replace function private.can_manage_provider_record(p_provider_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.is_user_active()
    and (
      private.is_system_admin()
      or (
        private.is_agency_admin()
        and exists (
          select 1
          from public.provider_agencies pa
          join public.user_agency_access uaa on uaa.agency_id = pa.agency_id
          where pa.provider_id = p_provider_id
            and pa.active = true
            and uaa.user_id = (select auth.uid())
            and uaa.can_manage_personnel = true
        )
      )
    );
$$;

create or replace function private.can_manage_agency_fleet(p_agency_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.is_user_active()
    and (
      private.is_system_admin()
      or (
        private.is_agency_admin()
        and exists (
          select 1
          from public.user_agency_access uaa
          where uaa.user_id = (select auth.uid())
            and uaa.agency_id = p_agency_id
            and uaa.can_manage_fleet = true
        )
      )
    );
$$;

revoke execute on function private.is_agency_admin() from public, anon;
revoke execute on function private.has_agency_access(uuid) from public, anon;
revoke execute on function private.can_manage_agency_personnel(uuid) from public, anon;
revoke execute on function private.can_manage_agency_credentials(uuid) from public, anon;
revoke execute on function private.can_view_provider(uuid) from public, anon;
revoke execute on function private.can_manage_provider_credentials(uuid) from public, anon;
revoke execute on function private.can_manage_provider_record(uuid) from public, anon;
revoke execute on function private.can_manage_agency_fleet(uuid) from public, anon;

grant execute on function private.is_agency_admin() to authenticated;
grant execute on function private.has_agency_access(uuid) to authenticated;
grant execute on function private.can_manage_agency_personnel(uuid) to authenticated;
grant execute on function private.can_manage_agency_credentials(uuid) to authenticated;
grant execute on function private.can_view_provider(uuid) to authenticated;
grant execute on function private.can_manage_provider_credentials(uuid) to authenticated;
grant execute on function private.can_manage_provider_record(uuid) to authenticated;
grant execute on function private.can_manage_agency_fleet(uuid) to authenticated;

-- Remove stale agency grants from accounts that are no longer administrators.
-- This prevents an old permission row from springing back to life unexpectedly.
delete from public.user_agency_access uaa
where not exists (
  select 1
  from public.user_roles ur
  where ur.user_id = uaa.user_id
    and ur.role in ('agency_admin', 'system_admin')
);

commit;

NOTIFY pgrst, 'reload schema';
