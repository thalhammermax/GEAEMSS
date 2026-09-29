-- GEAEMS Portal v0.6.4
-- Agency Administrator assignments must follow the linked provider's current
-- active agency affiliations. Unaffiliated agencies are not valid assignments.
-- Run after migrations 001 through 011.

begin;

-- -----------------------------------------------------------------------------
-- Clean up any legacy assignments that violate the new rule.
-- -----------------------------------------------------------------------------

delete from public.user_agency_access uaa
where not exists (
  select 1
  from public.profiles p
  join public.provider_agencies pa
    on pa.provider_id = p.provider_id
   and pa.agency_id = uaa.agency_id
   and pa.active = true
  join public.agencies a
    on a.id = pa.agency_id
   and a.active = true
  where p.id = uaa.user_id
);

delete from public.user_roles ur
where ur.role = 'agency_admin'
  and not exists (
    select 1
    from public.profiles p
    join public.provider_agencies pa
      on pa.provider_id = p.provider_id
     and pa.active = true
    join public.agencies a
      on a.id = pa.agency_id
     and a.active = true
    where p.id = ur.user_id
  );

-- -----------------------------------------------------------------------------
-- Database safety nets. The UI also removes invalid choices entirely.
-- -----------------------------------------------------------------------------

create or replace function private.enforce_agency_admin_role_affiliation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.role = 'agency_admin' and not exists (
    select 1
    from public.profiles p
    join public.provider_agencies pa
      on pa.provider_id = p.provider_id
     and pa.active = true
    join public.agencies a
      on a.id = pa.agency_id
     and a.active = true
    where p.id = new.user_id
  ) then
    raise exception 'Agency Administrator requires a linked provider with an active agency affiliation.'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

revoke execute on function private.enforce_agency_admin_role_affiliation() from public, anon, authenticated;

drop trigger if exists user_roles_agency_admin_affiliation_guard on public.user_roles;
create trigger user_roles_agency_admin_affiliation_guard
before insert or update on public.user_roles
for each row
execute function private.enforce_agency_admin_role_affiliation();

create or replace function private.enforce_user_agency_access_affiliation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1
    from public.user_roles ur
    where ur.user_id = new.user_id
      and ur.role = 'agency_admin'
  ) then
    raise exception 'Agency access requires the Agency Administrator role.'
      using errcode = '23514';
  end if;

  if not exists (
    select 1
    from public.profiles p
    join public.provider_agencies pa
      on pa.provider_id = p.provider_id
     and pa.agency_id = new.agency_id
     and pa.active = true
    join public.agencies a
      on a.id = pa.agency_id
     and a.active = true
    where p.id = new.user_id
  ) then
    raise exception 'Agency Administrator access may only be assigned to an agency where the linked provider has an active affiliation.'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

revoke execute on function private.enforce_user_agency_access_affiliation() from public, anon, authenticated;

drop trigger if exists user_agency_access_affiliation_guard on public.user_agency_access;
create trigger user_agency_access_affiliation_guard
before insert or update on public.user_agency_access
for each row
execute function private.enforce_user_agency_access_affiliation();

-- If a provider affiliation is ended, a profile is relinked, or an agency is
-- deactivated, remove agency-admin grants that are no longer valid. This avoids
-- stale permissions surviving after the underlying personnel record changes.
create or replace function private.cleanup_invalid_agency_admin_assignments()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.user_agency_access uaa
  where not exists (
    select 1
    from public.profiles p
    join public.provider_agencies pa
      on pa.provider_id = p.provider_id
     and pa.agency_id = uaa.agency_id
     and pa.active = true
    join public.agencies a
      on a.id = pa.agency_id
     and a.active = true
    where p.id = uaa.user_id
  );

  delete from public.user_roles ur
  where ur.role = 'agency_admin'
    and not exists (
      select 1
      from public.profiles p
      join public.provider_agencies pa
        on pa.provider_id = p.provider_id
       and pa.active = true
      join public.agencies a
        on a.id = pa.agency_id
       and a.active = true
      where p.id = ur.user_id
    );

  -- Return value is ignored for AFTER STATEMENT triggers.
  return null;
end;
$$;

revoke execute on function private.cleanup_invalid_agency_admin_assignments() from public, anon, authenticated;

drop trigger if exists provider_agencies_cleanup_agency_admin on public.provider_agencies;
create trigger provider_agencies_cleanup_agency_admin
after update or delete on public.provider_agencies
for each statement
execute function private.cleanup_invalid_agency_admin_assignments();

drop trigger if exists profiles_cleanup_agency_admin on public.profiles;
create trigger profiles_cleanup_agency_admin
after update of provider_id on public.profiles
for each statement
execute function private.cleanup_invalid_agency_admin_assignments();

drop trigger if exists agencies_cleanup_agency_admin on public.agencies;
create trigger agencies_cleanup_agency_admin
after update of active on public.agencies
for each statement
execute function private.cleanup_invalid_agency_admin_assignments();

commit;

NOTIFY pgrst, 'reload schema';
