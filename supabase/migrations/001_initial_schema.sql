-- EMS Credential Tracker - Initial Supabase Schema
-- Designed for ~800 providers / ~20 agencies, with room to scale substantially.
-- Run in a NEW Supabase project via SQL Editor, or apply as a migration with the Supabase CLI.

begin;

create extension if not exists pgcrypto;

create schema if not exists private;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated;

-- -----------------------------------------------------------------------------
-- Shared utility functions
-- -----------------------------------------------------------------------------

create or replace function private.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

revoke execute on function private.set_updated_at() from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- Core lookup tables
-- -----------------------------------------------------------------------------

create table public.provider_levels (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null unique,
  sort_order integer not null default 100,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.provider_statuses (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null unique,
  counts_toward_compliance boolean not null default true,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.agencies (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  short_name text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.providers (
  id uuid primary key default gen_random_uuid(),
  provider_number text unique,
  first_name text not null,
  middle_name text,
  last_name text not null,
  preferred_name text,
  email text,
  phone text,
  provider_level_id uuid references public.provider_levels(id) on delete restrict,
  provider_status_id uuid references public.provider_statuses(id) on delete restrict,
  system_entry_date date,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index providers_email_unique_ci
  on public.providers (lower(email))
  where email is not null and btrim(email) <> '';

create index providers_name_idx on public.providers (last_name, first_name);
create index providers_level_idx on public.providers (provider_level_id);
create index providers_status_idx on public.providers (provider_status_id);

create table public.provider_agencies (
  id uuid primary key default gen_random_uuid(),
  provider_id uuid not null references public.providers(id) on delete cascade,
  agency_id uuid not null references public.agencies(id) on delete cascade,
  employee_id text,
  agency_provider_level_id uuid references public.provider_levels(id) on delete restrict,
  start_date date,
  end_date date,
  is_primary boolean not null default false,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint provider_agencies_date_check check (end_date is null or start_date is null or end_date >= start_date)
);

create unique index provider_agencies_active_unique
  on public.provider_agencies(provider_id, agency_id)
  where active = true;

create unique index provider_agencies_one_primary
  on public.provider_agencies(provider_id)
  where active = true and is_primary = true;

create index provider_agencies_provider_idx on public.provider_agencies(provider_id);
create index provider_agencies_agency_idx on public.provider_agencies(agency_id);

-- -----------------------------------------------------------------------------
-- Authentication linkage and application authorization
-- -----------------------------------------------------------------------------

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  provider_id uuid unique references public.providers(id) on delete set null,
  display_name text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.user_roles (
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('system_admin', 'agency_admin', 'provider')),
  created_at timestamptz not null default now(),
  primary key (user_id, role)
);

create table public.user_agency_access (
  user_id uuid not null references auth.users(id) on delete cascade,
  agency_id uuid not null references public.agencies(id) on delete cascade,
  can_manage_personnel boolean not null default false,
  can_manage_credentials boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, agency_id)
);

create index user_agency_access_user_idx on public.user_agency_access(user_id);
create index user_agency_access_agency_idx on public.user_agency_access(agency_id);

-- -----------------------------------------------------------------------------
-- Credential configuration and records
-- -----------------------------------------------------------------------------

create table public.credential_types (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null unique,
  category text not null default 'Certification',
  description text,
  renewal_months integer check (renewal_months is null or renewal_months > 0),
  requires_number boolean not null default false,
  requires_issue_date boolean not null default false,
  requires_expiration_date boolean not null default true,
  requires_document boolean not null default false,
  requires_verification boolean not null default true,
  warning_days integer[] not null default array[120,90,60,30,14,7,1],
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.credential_requirements (
  id uuid primary key default gen_random_uuid(),
  credential_type_id uuid not null references public.credential_types(id) on delete cascade,
  scope_type text not null check (scope_type in ('system', 'agency')),
  agency_id uuid references public.agencies(id) on delete cascade,
  provider_level_id uuid references public.provider_levels(id) on delete cascade,
  required boolean not null default true,
  effective_start_date date,
  effective_end_date date,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint credential_requirements_scope_check check (
    (scope_type = 'system' and agency_id is null)
    or
    (scope_type = 'agency' and agency_id is not null)
  ),
  constraint credential_requirements_date_check check (
    effective_end_date is null
    or effective_start_date is null
    or effective_end_date >= effective_start_date
  )
);

create index credential_requirements_type_idx on public.credential_requirements(credential_type_id);
create index credential_requirements_agency_idx on public.credential_requirements(agency_id);
create index credential_requirements_level_idx on public.credential_requirements(provider_level_id);

create unique index credential_requirements_unique_system
  on public.credential_requirements (
    credential_type_id,
    coalesce(provider_level_id::text, 'ALL'),
    coalesce(effective_start_date, date '1900-01-01')
  )
  where scope_type = 'system';

create unique index credential_requirements_unique_agency
  on public.credential_requirements (
    credential_type_id,
    agency_id,
    coalesce(provider_level_id::text, 'ALL'),
    coalesce(effective_start_date, date '1900-01-01')
  )
  where scope_type = 'agency';

create table public.provider_credentials (
  id uuid primary key default gen_random_uuid(),
  provider_id uuid not null references public.providers(id) on delete cascade,
  credential_type_id uuid not null references public.credential_types(id) on delete restrict,
  credential_number text,
  issue_date date,
  expiration_date date,
  verification_status text not null default 'verified'
    check (verification_status in ('verified', 'rejected')),
  is_current boolean not null default true,
  verified_by uuid references auth.users(id) on delete set null,
  verified_at timestamptz,
  source text not null default 'manual',
  notes text,
  supersedes_credential_id uuid references public.provider_credentials(id) on delete set null,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint provider_credentials_date_check check (
    expiration_date is null or issue_date is null or expiration_date >= issue_date
  )
);

create unique index provider_credentials_one_current_verified
  on public.provider_credentials(provider_id, credential_type_id)
  where is_current = true and verification_status = 'verified';

create index provider_credentials_provider_idx on public.provider_credentials(provider_id);
create index provider_credentials_type_idx on public.provider_credentials(credential_type_id);
create index provider_credentials_expiration_idx on public.provider_credentials(expiration_date)
  where is_current = true and verification_status = 'verified';

create table public.credential_submissions (
  id uuid primary key default gen_random_uuid(),
  provider_id uuid not null references public.providers(id) on delete cascade,
  credential_type_id uuid not null references public.credential_types(id) on delete restrict,
  credential_number text,
  issue_date date,
  expiration_date date,
  status text not null default 'pending'
    check (status in ('pending', 'approved', 'rejected', 'changes_requested', 'withdrawn')),
  submitted_by uuid not null references auth.users(id) on delete restrict default auth.uid(),
  submitted_at timestamptz not null default now(),
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  review_notes text,
  resulting_credential_id uuid references public.provider_credentials(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint credential_submissions_date_check check (
    expiration_date is null or issue_date is null or expiration_date >= issue_date
  )
);

create index credential_submissions_provider_idx on public.credential_submissions(provider_id);
create index credential_submissions_status_idx on public.credential_submissions(status);
create index credential_submissions_type_idx on public.credential_submissions(credential_type_id);

create table public.credential_documents (
  id uuid primary key default gen_random_uuid(),
  provider_credential_id uuid references public.provider_credentials(id) on delete cascade,
  submission_id uuid references public.credential_submissions(id) on delete cascade,
  bucket_name text not null default 'credential-documents',
  object_path text not null,
  original_filename text,
  mime_type text,
  size_bytes bigint check (size_bytes is null or size_bytes >= 0),
  uploaded_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  constraint credential_documents_one_parent check (
    (provider_credential_id is not null and submission_id is null)
    or
    (provider_credential_id is null and submission_id is not null)
  )
);

create unique index credential_documents_object_unique
  on public.credential_documents(bucket_name, object_path);

-- -----------------------------------------------------------------------------
-- Notifications and auditing
-- -----------------------------------------------------------------------------

create table public.notification_history (
  id bigint generated always as identity primary key,
  provider_id uuid not null references public.providers(id) on delete cascade,
  provider_credential_id uuid references public.provider_credentials(id) on delete cascade,
  credential_type_id uuid not null references public.credential_types(id) on delete restrict,
  threshold_days integer,
  channel text not null default 'email' check (channel in ('email', 'in_app')),
  recipient text,
  status text not null default 'queued' check (status in ('queued', 'sent', 'failed', 'skipped')),
  provider_message_id text,
  error_message text,
  created_at timestamptz not null default now(),
  sent_at timestamptz
);

create unique index notification_history_dedupe
  on public.notification_history(provider_credential_id, threshold_days, channel, recipient)
  where provider_credential_id is not null and threshold_days is not null;

create index notification_history_provider_idx on public.notification_history(provider_id);
create index notification_history_status_idx on public.notification_history(status);

create table public.audit_log (
  id bigint generated always as identity primary key,
  actor_user_id uuid references auth.users(id) on delete set null,
  action text not null,
  entity_type text not null,
  entity_id uuid,
  old_data jsonb,
  new_data jsonb,
  created_at timestamptz not null default now()
);

create index audit_log_entity_idx on public.audit_log(entity_type, entity_id);
create index audit_log_actor_idx on public.audit_log(actor_user_id);
create index audit_log_created_idx on public.audit_log(created_at desc);

-- -----------------------------------------------------------------------------
-- Authorization helper functions (non-exposed schema)
-- -----------------------------------------------------------------------------

create or replace function private.is_system_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.user_roles ur
    where ur.user_id = (select auth.uid())
      and ur.role = 'system_admin'
  );
$$;

create or replace function private.my_provider_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select p.provider_id
  from public.profiles p
  where p.id = (select auth.uid())
    and p.active = true
  limit 1;
$$;

create or replace function private.has_agency_access(p_agency_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    private.is_system_admin()
    or exists (
      select 1
      from public.user_agency_access uaa
      where uaa.user_id = (select auth.uid())
        and uaa.agency_id = p_agency_id
    );
$$;

create or replace function private.can_manage_agency_personnel(p_agency_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    private.is_system_admin()
    or exists (
      select 1
      from public.user_agency_access uaa
      where uaa.user_id = (select auth.uid())
        and uaa.agency_id = p_agency_id
        and uaa.can_manage_personnel = true
    );
$$;

create or replace function private.can_manage_agency_credentials(p_agency_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    private.is_system_admin()
    or exists (
      select 1
      from public.user_agency_access uaa
      where uaa.user_id = (select auth.uid())
        and uaa.agency_id = p_agency_id
        and uaa.can_manage_credentials = true
    );
$$;

create or replace function private.is_self_provider(p_provider_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(private.my_provider_id() = p_provider_id, false);
$$;

create or replace function private.can_view_provider(p_provider_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    private.is_system_admin()
    or private.is_self_provider(p_provider_id)
    or exists (
      select 1
      from public.provider_agencies pa
      join public.user_agency_access uaa on uaa.agency_id = pa.agency_id
      where pa.provider_id = p_provider_id
        and pa.active = true
        and uaa.user_id = (select auth.uid())
    );
$$;

create or replace function private.can_manage_provider_credentials(p_provider_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    private.is_system_admin()
    or exists (
      select 1
      from public.provider_agencies pa
      join public.user_agency_access uaa on uaa.agency_id = pa.agency_id
      where pa.provider_id = p_provider_id
        and pa.active = true
        and uaa.user_id = (select auth.uid())
        and uaa.can_manage_credentials = true
    );
$$;

revoke execute on function private.is_system_admin() from public, anon;
revoke execute on function private.my_provider_id() from public, anon;
revoke execute on function private.has_agency_access(uuid) from public, anon;
revoke execute on function private.can_manage_agency_personnel(uuid) from public, anon;
revoke execute on function private.can_manage_agency_credentials(uuid) from public, anon;
revoke execute on function private.is_self_provider(uuid) from public, anon;
revoke execute on function private.can_view_provider(uuid) from public, anon;
revoke execute on function private.can_manage_provider_credentials(uuid) from public, anon;

grant execute on function private.is_system_admin() to authenticated;
grant execute on function private.my_provider_id() to authenticated;
grant execute on function private.has_agency_access(uuid) to authenticated;
grant execute on function private.can_manage_agency_personnel(uuid) to authenticated;
grant execute on function private.can_manage_agency_credentials(uuid) to authenticated;
grant execute on function private.is_self_provider(uuid) to authenticated;
grant execute on function private.can_view_provider(uuid) to authenticated;
grant execute on function private.can_manage_provider_credentials(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- Audit trigger
-- -----------------------------------------------------------------------------

create or replace function private.audit_row_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_entity_id uuid;
begin
  if tg_op = 'DELETE' then
    begin
      v_entity_id := old.id;
    exception when others then
      v_entity_id := null;
    end;

    insert into public.audit_log(actor_user_id, action, entity_type, entity_id, old_data, new_data)
    values ((select auth.uid()), lower(tg_op), tg_table_name, v_entity_id, to_jsonb(old), null);
    return old;
  else
    begin
      v_entity_id := new.id;
    exception when others then
      v_entity_id := null;
    end;

    insert into public.audit_log(actor_user_id, action, entity_type, entity_id, old_data, new_data)
    values (
      (select auth.uid()),
      lower(tg_op),
      tg_table_name,
      v_entity_id,
      case when tg_op = 'UPDATE' then to_jsonb(old) else null end,
      to_jsonb(new)
    );
    return new;
  end if;
end;
$$;

revoke execute on function private.audit_row_change() from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- Credential submission approval/rejection RPCs
-- -----------------------------------------------------------------------------

create or replace function public.approve_credential_submission(
  p_submission_id uuid,
  p_review_notes text default null
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_submission public.credential_submissions%rowtype;
  v_old_credential_id uuid;
  v_new_credential_id uuid;
begin
  select * into v_submission
  from public.credential_submissions
  where id = p_submission_id
  for update;

  if not found then
    raise exception 'Credential submission not found';
  end if;

  if v_submission.status <> 'pending' and v_submission.status <> 'changes_requested' then
    raise exception 'Credential submission is not reviewable in status %', v_submission.status;
  end if;

  if not private.can_manage_provider_credentials(v_submission.provider_id) then
    raise exception 'Not authorized to approve credentials for this provider';
  end if;

  select id into v_old_credential_id
  from public.provider_credentials
  where provider_id = v_submission.provider_id
    and credential_type_id = v_submission.credential_type_id
    and is_current = true
    and verification_status = 'verified'
  for update;

  if v_old_credential_id is not null then
    update public.provider_credentials
    set is_current = false,
        updated_at = now()
    where id = v_old_credential_id;
  end if;

  insert into public.provider_credentials (
    provider_id,
    credential_type_id,
    credential_number,
    issue_date,
    expiration_date,
    verification_status,
    is_current,
    verified_by,
    verified_at,
    source,
    supersedes_credential_id,
    created_by
  )
  values (
    v_submission.provider_id,
    v_submission.credential_type_id,
    v_submission.credential_number,
    v_submission.issue_date,
    v_submission.expiration_date,
    'verified',
    true,
    (select auth.uid()),
    now(),
    'provider_submission',
    v_old_credential_id,
    v_submission.submitted_by
  )
  returning id into v_new_credential_id;

  update public.credential_documents
  set provider_credential_id = v_new_credential_id,
      submission_id = null
  where submission_id = p_submission_id;

  update public.credential_submissions
  set status = 'approved',
      reviewed_by = (select auth.uid()),
      reviewed_at = now(),
      review_notes = p_review_notes,
      resulting_credential_id = v_new_credential_id,
      updated_at = now()
  where id = p_submission_id;

  return v_new_credential_id;
end;
$$;

create or replace function public.reject_credential_submission(
  p_submission_id uuid,
  p_review_notes text
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_provider_id uuid;
begin
  select provider_id into v_provider_id
  from public.credential_submissions
  where id = p_submission_id
  for update;

  if v_provider_id is null then
    raise exception 'Credential submission not found';
  end if;

  if not private.can_manage_provider_credentials(v_provider_id) then
    raise exception 'Not authorized to reject credentials for this provider';
  end if;

  update public.credential_submissions
  set status = 'rejected',
      reviewed_by = (select auth.uid()),
      reviewed_at = now(),
      review_notes = p_review_notes,
      updated_at = now()
  where id = p_submission_id
    and status in ('pending', 'changes_requested');
end;
$$;

revoke execute on function public.approve_credential_submission(uuid, text) from public, anon;
revoke execute on function public.reject_credential_submission(uuid, text) from public, anon;
grant execute on function public.approve_credential_submission(uuid, text) to authenticated;
grant execute on function public.reject_credential_submission(uuid, text) to authenticated;

-- -----------------------------------------------------------------------------
-- Updated-at triggers
-- -----------------------------------------------------------------------------

do $$
declare
  t text;
begin
  foreach t in array array[
    'provider_levels','provider_statuses','agencies','providers','provider_agencies',
    'profiles','user_agency_access','credential_types','credential_requirements',
    'provider_credentials','credential_submissions'
  ]
  loop
    execute format('create trigger %I before update on public.%I for each row execute function private.set_updated_at()', 'set_' || t || '_updated_at', t);
  end loop;
end $$;

-- -----------------------------------------------------------------------------
-- Audit triggers
-- -----------------------------------------------------------------------------

do $$
declare
  t text;
begin
  foreach t in array array[
    'providers','provider_agencies','credential_types','credential_requirements',
    'provider_credentials','credential_submissions','user_roles','user_agency_access'
  ]
  loop
    execute format('create trigger %I after insert or update or delete on public.%I for each row execute function private.audit_row_change()', 'audit_' || t, t);
  end loop;
end $$;

-- -----------------------------------------------------------------------------
-- RLS + grants
-- -----------------------------------------------------------------------------

alter table public.provider_levels enable row level security;
alter table public.provider_statuses enable row level security;
alter table public.agencies enable row level security;
alter table public.providers enable row level security;
alter table public.provider_agencies enable row level security;
alter table public.profiles enable row level security;
alter table public.user_roles enable row level security;
alter table public.user_agency_access enable row level security;
alter table public.credential_types enable row level security;
alter table public.credential_requirements enable row level security;
alter table public.provider_credentials enable row level security;
alter table public.credential_submissions enable row level security;
alter table public.credential_documents enable row level security;
alter table public.notification_history enable row level security;
alter table public.audit_log enable row level security;

revoke all on all tables in schema public from anon;
revoke all on all tables in schema public from authenticated;

grant select on public.provider_levels, public.provider_statuses, public.credential_types to authenticated;
grant select on public.agencies, public.providers, public.provider_agencies to authenticated;
grant select on public.profiles, public.user_roles, public.user_agency_access to authenticated;
grant select on public.credential_requirements, public.provider_credentials, public.credential_submissions, public.credential_documents to authenticated;
grant select on public.notification_history, public.audit_log to authenticated;

grant insert, update, delete on public.provider_levels, public.provider_statuses, public.agencies to authenticated;
grant insert, update, delete on public.providers, public.provider_agencies to authenticated;
grant insert, update, delete on public.profiles, public.user_roles, public.user_agency_access to authenticated;
grant insert, update, delete on public.credential_types, public.credential_requirements to authenticated;
grant insert, update, delete on public.provider_credentials, public.credential_submissions, public.credential_documents to authenticated;

-- Lookup tables
create policy provider_levels_read on public.provider_levels
for select to authenticated using (true);
create policy provider_levels_admin_write on public.provider_levels
for all to authenticated using ((select private.is_system_admin())) with check ((select private.is_system_admin()));

create policy provider_statuses_read on public.provider_statuses
for select to authenticated using (true);
create policy provider_statuses_admin_write on public.provider_statuses
for all to authenticated using ((select private.is_system_admin())) with check ((select private.is_system_admin()));

-- Agencies
create policy agencies_read on public.agencies
for select to authenticated
using (
  (select private.is_system_admin())
  or (select private.has_agency_access(id))
  or exists (
    select 1 from public.provider_agencies pa
    where pa.agency_id = agencies.id
      and pa.provider_id = (select private.my_provider_id())
      and pa.active = true
  )
);

create policy agencies_admin_insert on public.agencies
for insert to authenticated with check ((select private.is_system_admin()));
create policy agencies_admin_update on public.agencies
for update to authenticated using ((select private.is_system_admin())) with check ((select private.is_system_admin()));
create policy agencies_admin_delete on public.agencies
for delete to authenticated using ((select private.is_system_admin()));

-- Profiles
create policy profiles_read on public.profiles
for select to authenticated
using (id = (select auth.uid()) or (select private.is_system_admin()));

create policy profiles_admin_insert on public.profiles
for insert to authenticated with check ((select private.is_system_admin()));
create policy profiles_admin_update on public.profiles
for update to authenticated using ((select private.is_system_admin())) with check ((select private.is_system_admin()));
create policy profiles_admin_delete on public.profiles
for delete to authenticated using ((select private.is_system_admin()));

-- Roles/access
create policy user_roles_read on public.user_roles
for select to authenticated
using (user_id = (select auth.uid()) or (select private.is_system_admin()));
create policy user_roles_admin_write on public.user_roles
for all to authenticated using ((select private.is_system_admin())) with check ((select private.is_system_admin()));

create policy user_agency_access_read on public.user_agency_access
for select to authenticated
using (user_id = (select auth.uid()) or (select private.is_system_admin()));
create policy user_agency_access_admin_write on public.user_agency_access
for all to authenticated using ((select private.is_system_admin())) with check ((select private.is_system_admin()));

-- Providers
create policy providers_read on public.providers
for select to authenticated using ((select private.can_view_provider(id)));

create policy providers_system_admin_insert on public.providers
for insert to authenticated with check ((select private.is_system_admin()));
create policy providers_system_admin_update on public.providers
for update to authenticated using ((select private.is_system_admin())) with check ((select private.is_system_admin()));
create policy providers_system_admin_delete on public.providers
for delete to authenticated using ((select private.is_system_admin()));

-- Provider agency affiliations
create policy provider_agencies_read on public.provider_agencies
for select to authenticated
using (
  (select private.is_system_admin())
  or provider_id = (select private.my_provider_id())
  or (select private.has_agency_access(agency_id))
);

create policy provider_agencies_insert on public.provider_agencies
for insert to authenticated
with check ((select private.can_manage_agency_personnel(agency_id)));
create policy provider_agencies_update on public.provider_agencies
for update to authenticated
using ((select private.can_manage_agency_personnel(agency_id)))
with check ((select private.can_manage_agency_personnel(agency_id)));
create policy provider_agencies_delete on public.provider_agencies
for delete to authenticated
using ((select private.can_manage_agency_personnel(agency_id)));

-- Credential type definitions
create policy credential_types_read on public.credential_types
for select to authenticated using (true);
create policy credential_types_admin_write on public.credential_types
for all to authenticated using ((select private.is_system_admin())) with check ((select private.is_system_admin()));

-- Credential requirements
create policy credential_requirements_read on public.credential_requirements
for select to authenticated
using (
  (select private.is_system_admin())
  or scope_type = 'system'
  or (scope_type = 'agency' and (
    (select private.has_agency_access(agency_id))
    or exists (
      select 1 from public.provider_agencies pa
      where pa.agency_id = credential_requirements.agency_id
        and pa.provider_id = (select private.my_provider_id())
        and pa.active = true
    )
  ))
);

create policy credential_requirements_admin_write on public.credential_requirements
for all to authenticated using ((select private.is_system_admin())) with check ((select private.is_system_admin()));

-- Verified credential records
create policy provider_credentials_read on public.provider_credentials
for select to authenticated using ((select private.can_view_provider(provider_id)));

create policy provider_credentials_admin_insert on public.provider_credentials
for insert to authenticated with check ((select private.can_manage_provider_credentials(provider_id)));
create policy provider_credentials_admin_update on public.provider_credentials
for update to authenticated
using ((select private.can_manage_provider_credentials(provider_id)))
with check ((select private.can_manage_provider_credentials(provider_id)));
create policy provider_credentials_admin_delete on public.provider_credentials
for delete to authenticated using ((select private.is_system_admin()));

-- Provider submissions
create policy credential_submissions_read on public.credential_submissions
for select to authenticated using ((select private.can_view_provider(provider_id)));

create policy credential_submissions_insert on public.credential_submissions
for insert to authenticated
with check (
  submitted_by = (select auth.uid())
  and (
    provider_id = (select private.my_provider_id())
    or (select private.can_manage_provider_credentials(provider_id))
  )
);

create policy credential_submissions_provider_withdraw on public.credential_submissions
for update to authenticated
using (
  provider_id = (select private.my_provider_id())
  and submitted_by = (select auth.uid())
  and status in ('pending', 'changes_requested')
)
with check (
  provider_id = (select private.my_provider_id())
  and submitted_by = (select auth.uid())
  and status in ('pending', 'withdrawn')
);

create policy credential_submissions_admin_update on public.credential_submissions
for update to authenticated
using ((select private.can_manage_provider_credentials(provider_id)))
with check ((select private.can_manage_provider_credentials(provider_id)));

create policy credential_submissions_admin_delete on public.credential_submissions
for delete to authenticated using ((select private.is_system_admin()));

-- Credential document metadata
create policy credential_documents_read on public.credential_documents
for select to authenticated
using (
  (provider_credential_id is not null and exists (
    select 1 from public.provider_credentials pc
    where pc.id = credential_documents.provider_credential_id
      and (select private.can_view_provider(pc.provider_id))
  ))
  or
  (submission_id is not null and exists (
    select 1 from public.credential_submissions cs
    where cs.id = credential_documents.submission_id
      and (select private.can_view_provider(cs.provider_id))
  ))
);

create policy credential_documents_insert on public.credential_documents
for insert to authenticated
with check (
  uploaded_by = (select auth.uid())
  and (
    (provider_credential_id is not null and exists (
      select 1 from public.provider_credentials pc
      where pc.id = credential_documents.provider_credential_id
        and (select private.can_manage_provider_credentials(pc.provider_id))
    ))
    or
    (submission_id is not null and exists (
      select 1 from public.credential_submissions cs
      where cs.id = credential_documents.submission_id
        and (
          cs.provider_id = (select private.my_provider_id())
          or (select private.can_manage_provider_credentials(cs.provider_id))
        )
    ))
  )
);

create policy credential_documents_admin_update on public.credential_documents
for update to authenticated
using (
  (provider_credential_id is not null and exists (
    select 1 from public.provider_credentials pc
    where pc.id = credential_documents.provider_credential_id
      and (select private.can_manage_provider_credentials(pc.provider_id))
  ))
  or
  (submission_id is not null and exists (
    select 1 from public.credential_submissions cs
    where cs.id = credential_documents.submission_id
      and (select private.can_manage_provider_credentials(cs.provider_id))
  ))
)
with check (
  (provider_credential_id is not null and exists (
    select 1 from public.provider_credentials pc
    where pc.id = credential_documents.provider_credential_id
      and (select private.can_manage_provider_credentials(pc.provider_id))
  ))
  or
  (submission_id is not null and exists (
    select 1 from public.credential_submissions cs
    where cs.id = credential_documents.submission_id
      and (select private.can_manage_provider_credentials(cs.provider_id))
  ))
);

create policy credential_documents_delete on public.credential_documents
for delete to authenticated
using (
  (select private.is_system_admin())
  or
  (submission_id is not null and exists (
    select 1 from public.credential_submissions cs
    where cs.id = credential_documents.submission_id
      and (
        (cs.provider_id = (select private.my_provider_id()) and cs.status = 'pending')
        or (select private.can_manage_provider_credentials(cs.provider_id))
      )
  ))
);

-- Notification history: read-only to app users; inserts happen via service role / scheduled jobs later.
create policy notification_history_read on public.notification_history
for select to authenticated using ((select private.can_view_provider(provider_id)));

-- Audit log: System Admin only.
create policy audit_log_system_admin_read on public.audit_log
for select to authenticated using ((select private.is_system_admin()));

-- -----------------------------------------------------------------------------
-- Security-invoker views for app dashboards
-- -----------------------------------------------------------------------------

create or replace view public.current_provider_credentials
with (security_invoker = true)
as
select
  pc.id,
  pc.provider_id,
  pc.credential_type_id,
  ct.code as credential_code,
  ct.name as credential_name,
  ct.category,
  pc.credential_number,
  pc.issue_date,
  pc.expiration_date,
  case
    when pc.expiration_date is null then 'CURRENT'
    when pc.expiration_date < current_date then 'EXPIRED'
    when pc.expiration_date <= current_date + coalesce((select max(d) from unnest(ct.warning_days) d), 90) then 'EXPIRING_SOON'
    else 'CURRENT'
  end as status,
  case
    when pc.expiration_date is null then null
    else (pc.expiration_date - current_date)
  end as days_remaining,
  pc.verified_by,
  pc.verified_at,
  pc.source,
  pc.updated_at
from public.provider_credentials pc
join public.credential_types ct on ct.id = pc.credential_type_id
where pc.is_current = true
  and pc.verification_status = 'verified';

grant select on public.current_provider_credentials to authenticated;

create or replace view public.provider_compliance
with (security_invoker = true)
as
with required_pairs as (
  select distinct p.id as provider_id, cr.credential_type_id
  from public.providers p
  join public.credential_requirements cr
    on cr.scope_type = 'system'
   and cr.required = true
   and (cr.provider_level_id is null or cr.provider_level_id = p.provider_level_id)
   and (cr.effective_start_date is null or cr.effective_start_date <= current_date)
   and (cr.effective_end_date is null or cr.effective_end_date >= current_date)

  union

  select distinct p.id as provider_id, cr.credential_type_id
  from public.providers p
  join public.provider_agencies pa
    on pa.provider_id = p.id
   and pa.active = true
  join public.credential_requirements cr
    on cr.scope_type = 'agency'
   and cr.agency_id = pa.agency_id
   and cr.required = true
   and (cr.provider_level_id is null or cr.provider_level_id = p.provider_level_id)
   and (cr.effective_start_date is null or cr.effective_start_date <= current_date)
   and (cr.effective_end_date is null or cr.effective_end_date >= current_date)
)
select
  rp.provider_id,
  p.first_name,
  p.last_name,
  p.provider_level_id,
  rp.credential_type_id,
  ct.code as credential_code,
  ct.name as credential_name,
  pc.id as provider_credential_id,
  pc.expiration_date,
  case
    when pc.id is null then 'MISSING'
    when pc.expiration_date is not null and pc.expiration_date < current_date then 'EXPIRED'
    when pc.expiration_date is not null
      and pc.expiration_date <= current_date + coalesce((select max(d) from unnest(ct.warning_days) d), 90)
      then 'EXPIRING_SOON'
    else 'CURRENT'
  end as compliance_status,
  case when pc.expiration_date is null then null else (pc.expiration_date - current_date) end as days_remaining
from required_pairs rp
join public.providers p on p.id = rp.provider_id
join public.credential_types ct on ct.id = rp.credential_type_id
left join public.provider_credentials pc
  on pc.provider_id = rp.provider_id
 and pc.credential_type_id = rp.credential_type_id
 and pc.is_current = true
 and pc.verification_status = 'verified';

grant select on public.provider_compliance to authenticated;

-- -----------------------------------------------------------------------------
-- Seed common lookup values (fully editable later)
-- -----------------------------------------------------------------------------

insert into public.provider_levels(code, name, sort_order)
values
  ('EMR', 'Emergency Medical Responder', 10),
  ('EMT', 'Emergency Medical Technician', 20),
  ('AEMT', 'Advanced Emergency Medical Technician', 30),
  ('PARAMEDIC', 'Paramedic', 40),
  ('PHRN', 'Pre-Hospital Registered Nurse', 50)
on conflict (code) do nothing;

insert into public.provider_statuses(code, name, counts_toward_compliance)
values
  ('ACTIVE', 'Active', true),
  ('LOA', 'Leave of Absence', false),
  ('INACTIVE', 'Inactive', false)
on conflict (code) do nothing;

-- Example credential types only; keep/delete/rename as desired.
insert into public.credential_types(
  code, name, category, renewal_months,
  requires_number, requires_issue_date, requires_expiration_date,
  requires_document, requires_verification
)
values
  ('IL_EMT', 'Illinois EMT License', 'State License', 48, true, false, true, false, true),
  ('IL_PARAMEDIC', 'Illinois Paramedic License', 'State License', 48, true, false, true, false, true),
  ('IL_PHRN', 'Illinois PHRN License', 'State License', 48, true, false, true, false, true),
  ('BLS', 'BLS Provider', 'Certification', 24, false, false, true, false, true),
  ('ACLS', 'ACLS Provider', 'Certification', 24, false, false, true, false, true),
  ('PALS', 'PALS Provider', 'Certification', 24, false, false, true, false, true)
on conflict (code) do nothing;

-- =============================================================================
-- Fleet licensing and inspection module
-- Added before first deployment so personnel and fleet compliance share the
-- same agencies, authorization model, dashboards, auditing, and future alerts.
-- =============================================================================

-- Agency-level permission for fleet management. System admins always retain
-- full access through the helper functions below.
alter table public.user_agency_access
  add column can_manage_fleet boolean not null default false;

-- -----------------------------------------------------------------------------
-- Fleet lookup and vehicle tables
-- -----------------------------------------------------------------------------

create table public.vehicle_types (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null unique,
  description text,
  active boolean not null default true,
  sort_order integer not null default 100,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.vehicle_statuses (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null unique,
  counts_toward_compliance boolean not null default true,
  active boolean not null default true,
  sort_order integer not null default 100,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.vehicles (
  id uuid primary key default gen_random_uuid(),
  agency_id uuid not null references public.agencies(id) on delete restrict,
  vehicle_type_id uuid references public.vehicle_types(id) on delete restrict,
  vehicle_status_id uuid references public.vehicle_statuses(id) on delete restrict,
  unit_number text,
  fleet_number text,
  vin text unique,
  year integer check (year is null or year between 1900 and 2200),
  make text,
  model text,
  license_plate text,
  license_plate_state text,
  in_service_date date,
  retired_date date,
  notes text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint vehicles_service_date_check check (
    retired_date is null or in_service_date is null or retired_date >= in_service_date
  )
);

create unique index vehicles_agency_unit_number_unique_ci
  on public.vehicles (agency_id, lower(unit_number))
  where active = true and unit_number is not null and btrim(unit_number) <> '';

create index vehicles_agency_idx on public.vehicles(agency_id);
create index vehicles_type_idx on public.vehicles(vehicle_type_id);
create index vehicles_status_idx on public.vehicles(vehicle_status_id);
create index vehicles_plate_idx on public.vehicles(license_plate, license_plate_state);

-- -----------------------------------------------------------------------------
-- Vehicle licensing
-- -----------------------------------------------------------------------------

create table public.vehicle_license_types (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null unique,
  category text not null default 'Vehicle License',
  description text,
  issuing_authority text,
  renewal_months integer check (renewal_months is null or renewal_months > 0),
  requires_number boolean not null default true,
  requires_issue_date boolean not null default false,
  requires_expiration_date boolean not null default true,
  requires_document boolean not null default false,
  warning_days integer[] not null default array[120,90,60,30,14,7,1],
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.vehicle_license_requirements (
  id uuid primary key default gen_random_uuid(),
  vehicle_license_type_id uuid not null references public.vehicle_license_types(id) on delete cascade,
  scope_type text not null check (scope_type in ('system', 'agency')),
  agency_id uuid references public.agencies(id) on delete cascade,
  vehicle_type_id uuid references public.vehicle_types(id) on delete cascade,
  required boolean not null default true,
  effective_start_date date,
  effective_end_date date,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint vehicle_license_requirements_scope_check check (
    (scope_type = 'system' and agency_id is null)
    or
    (scope_type = 'agency' and agency_id is not null)
  ),
  constraint vehicle_license_requirements_date_check check (
    effective_end_date is null
    or effective_start_date is null
    or effective_end_date >= effective_start_date
  )
);

create index vehicle_license_requirements_type_idx
  on public.vehicle_license_requirements(vehicle_license_type_id);
create index vehicle_license_requirements_agency_idx
  on public.vehicle_license_requirements(agency_id);
create index vehicle_license_requirements_vehicle_type_idx
  on public.vehicle_license_requirements(vehicle_type_id);

create table public.vehicle_licenses (
  id uuid primary key default gen_random_uuid(),
  vehicle_id uuid not null references public.vehicles(id) on delete cascade,
  vehicle_license_type_id uuid not null references public.vehicle_license_types(id) on delete restrict,
  license_number text,
  issuing_authority text,
  issue_date date,
  expiration_date date,
  verification_status text not null default 'verified'
    check (verification_status in ('verified', 'rejected')),
  is_current boolean not null default true,
  verified_by uuid references auth.users(id) on delete set null,
  verified_at timestamptz,
  source text not null default 'manual',
  notes text,
  supersedes_vehicle_license_id uuid references public.vehicle_licenses(id) on delete set null,
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint vehicle_licenses_date_check check (
    expiration_date is null or issue_date is null or expiration_date >= issue_date
  )
);

create unique index vehicle_licenses_one_current_verified
  on public.vehicle_licenses(vehicle_id, vehicle_license_type_id)
  where is_current = true and verification_status = 'verified';

create index vehicle_licenses_vehicle_idx on public.vehicle_licenses(vehicle_id);
create index vehicle_licenses_type_idx on public.vehicle_licenses(vehicle_license_type_id);
create index vehicle_licenses_expiration_idx on public.vehicle_licenses(expiration_date)
  where is_current = true and verification_status = 'verified';

-- -----------------------------------------------------------------------------
-- Vehicle inspections and deficiencies
-- -----------------------------------------------------------------------------

create table public.inspection_types (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null unique,
  description text,
  default_interval_months integer check (default_interval_months is null or default_interval_months > 0),
  requires_document boolean not null default false,
  tracks_deficiencies boolean not null default true,
  warning_days integer[] not null default array[90,60,30,14,7,1],
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.vehicle_inspection_requirements (
  id uuid primary key default gen_random_uuid(),
  inspection_type_id uuid not null references public.inspection_types(id) on delete cascade,
  scope_type text not null check (scope_type in ('system', 'agency')),
  agency_id uuid references public.agencies(id) on delete cascade,
  vehicle_type_id uuid references public.vehicle_types(id) on delete cascade,
  required boolean not null default true,
  interval_months_override integer check (interval_months_override is null or interval_months_override > 0),
  effective_start_date date,
  effective_end_date date,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint vehicle_inspection_requirements_scope_check check (
    (scope_type = 'system' and agency_id is null)
    or
    (scope_type = 'agency' and agency_id is not null)
  ),
  constraint vehicle_inspection_requirements_date_check check (
    effective_end_date is null
    or effective_start_date is null
    or effective_end_date >= effective_start_date
  )
);

create index vehicle_inspection_requirements_type_idx
  on public.vehicle_inspection_requirements(inspection_type_id);
create index vehicle_inspection_requirements_agency_idx
  on public.vehicle_inspection_requirements(agency_id);
create index vehicle_inspection_requirements_vehicle_type_idx
  on public.vehicle_inspection_requirements(vehicle_type_id);

create table public.vehicle_inspections (
  id uuid primary key default gen_random_uuid(),
  vehicle_id uuid not null references public.vehicles(id) on delete cascade,
  inspection_type_id uuid not null references public.inspection_types(id) on delete restrict,
  inspection_date date not null,
  result text not null check (
    result in ('passed', 'passed_with_deficiencies', 'failed', 'out_of_service')
  ),
  next_due_date date,
  inspector_name text,
  inspector_organization text,
  inspection_location text,
  odometer integer check (odometer is null or odometer >= 0),
  notes text,
  recorded_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint vehicle_inspections_next_due_check check (
    next_due_date is null or next_due_date >= inspection_date
  )
);

create index vehicle_inspections_vehicle_idx
  on public.vehicle_inspections(vehicle_id, inspection_date desc);
create index vehicle_inspections_type_idx
  on public.vehicle_inspections(inspection_type_id, inspection_date desc);
create index vehicle_inspections_next_due_idx
  on public.vehicle_inspections(next_due_date) where next_due_date is not null;

-- One active schedule row per vehicle/inspection type powers dashboard due dates
-- and future automated reminders, including vehicles with no completed inspection yet.
create table public.vehicle_inspection_schedules (
  id uuid primary key default gen_random_uuid(),
  vehicle_id uuid not null references public.vehicles(id) on delete cascade,
  inspection_type_id uuid not null references public.inspection_types(id) on delete cascade,
  next_due_date date not null,
  interval_months_override integer check (interval_months_override is null or interval_months_override > 0),
  last_inspection_id uuid references public.vehicle_inspections(id) on delete set null,
  active boolean not null default true,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(vehicle_id, inspection_type_id)
);

create index vehicle_inspection_schedules_due_idx
  on public.vehicle_inspection_schedules(next_due_date) where active = true;

create table public.vehicle_inspection_deficiencies (
  id uuid primary key default gen_random_uuid(),
  vehicle_inspection_id uuid not null references public.vehicle_inspections(id) on delete cascade,
  description text not null,
  severity text not null default 'deficiency'
    check (severity in ('advisory', 'deficiency', 'critical')),
  status text not null default 'open'
    check (status in ('open', 'corrected', 'waived')),
  correction_due_date date,
  corrected_at timestamptz,
  corrected_by uuid references auth.users(id) on delete set null,
  correction_notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index vehicle_inspection_deficiencies_inspection_idx
  on public.vehicle_inspection_deficiencies(vehicle_inspection_id);
create index vehicle_inspection_deficiencies_status_idx
  on public.vehicle_inspection_deficiencies(status, correction_due_date);

create table public.vehicle_documents (
  id uuid primary key default gen_random_uuid(),
  vehicle_license_id uuid references public.vehicle_licenses(id) on delete cascade,
  vehicle_inspection_id uuid references public.vehicle_inspections(id) on delete cascade,
  deficiency_id uuid references public.vehicle_inspection_deficiencies(id) on delete cascade,
  bucket_name text not null default 'vehicle-documents',
  object_path text not null,
  original_filename text,
  mime_type text,
  size_bytes bigint check (size_bytes is null or size_bytes >= 0),
  document_kind text,
  uploaded_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  constraint vehicle_documents_one_parent check (
    ((vehicle_license_id is not null)::int
     + (vehicle_inspection_id is not null)::int
     + (deficiency_id is not null)::int) = 1
  )
);

create unique index vehicle_documents_object_unique
  on public.vehicle_documents(bucket_name, object_path);

-- Future alert engine will write here. It is separate from provider credential
-- notifications so fleet reminders can target agency/system contacts cleanly.
create table public.fleet_notification_history (
  id bigint generated always as identity primary key,
  vehicle_id uuid not null references public.vehicles(id) on delete cascade,
  agency_id uuid not null references public.agencies(id) on delete cascade,
  notification_type text not null check (
    notification_type in ('license_expiration', 'inspection_due', 'deficiency_due')
  ),
  source_entity_id uuid,
  threshold_days integer,
  channel text not null default 'email' check (channel in ('email', 'in_app')),
  recipient text,
  status text not null default 'queued' check (status in ('queued', 'sent', 'failed', 'skipped')),
  provider_message_id text,
  error_message text,
  created_at timestamptz not null default now(),
  sent_at timestamptz
);

create unique index fleet_notification_history_dedupe
  on public.fleet_notification_history(
    vehicle_id, notification_type, source_entity_id, threshold_days, channel, recipient
  )
  where source_entity_id is not null and threshold_days is not null;

create index fleet_notification_history_vehicle_idx
  on public.fleet_notification_history(vehicle_id);
create index fleet_notification_history_agency_idx
  on public.fleet_notification_history(agency_id);
create index fleet_notification_history_status_idx
  on public.fleet_notification_history(status);

-- -----------------------------------------------------------------------------
-- Fleet authorization helpers
-- -----------------------------------------------------------------------------

create or replace function private.can_manage_agency_fleet(p_agency_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    private.is_system_admin()
    or exists (
      select 1
      from public.user_agency_access uaa
      where uaa.user_id = (select auth.uid())
        and uaa.agency_id = p_agency_id
        and uaa.can_manage_fleet = true
    );
$$;

create or replace function private.can_view_vehicle(p_vehicle_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.vehicles v
    where v.id = p_vehicle_id
      and private.has_agency_access(v.agency_id)
  );
$$;

create or replace function private.can_manage_vehicle(p_vehicle_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.vehicles v
    where v.id = p_vehicle_id
      and private.can_manage_agency_fleet(v.agency_id)
  );
$$;

revoke execute on function private.can_manage_agency_fleet(uuid) from public, anon;
revoke execute on function private.can_view_vehicle(uuid) from public, anon;
revoke execute on function private.can_manage_vehicle(uuid) from public, anon;
grant execute on function private.can_manage_agency_fleet(uuid) to authenticated;
grant execute on function private.can_view_vehicle(uuid) to authenticated;
grant execute on function private.can_manage_vehicle(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- Updated-at and audit triggers for fleet tables
-- -----------------------------------------------------------------------------

do $$
declare
  t text;
begin
  foreach t in array array[
    'vehicle_types','vehicle_statuses','vehicles','vehicle_license_types',
    'vehicle_license_requirements','vehicle_licenses','inspection_types',
    'vehicle_inspection_requirements','vehicle_inspections',
    'vehicle_inspection_schedules','vehicle_inspection_deficiencies'
  ]
  loop
    execute format(
      'create trigger %I before update on public.%I for each row execute function private.set_updated_at()',
      'set_' || t || '_updated_at', t
    );
  end loop;
end $$;

do $$
declare
  t text;
begin
  foreach t in array array[
    'vehicles','vehicle_license_types','vehicle_license_requirements','vehicle_licenses',
    'inspection_types','vehicle_inspection_requirements','vehicle_inspections',
    'vehicle_inspection_schedules','vehicle_inspection_deficiencies'
  ]
  loop
    execute format(
      'create trigger %I after insert or update or delete on public.%I for each row execute function private.audit_row_change()',
      'audit_' || t, t
    );
  end loop;
end $$;

-- -----------------------------------------------------------------------------
-- Fleet RLS
-- -----------------------------------------------------------------------------

alter table public.vehicle_types enable row level security;
alter table public.vehicle_statuses enable row level security;
alter table public.vehicles enable row level security;
alter table public.vehicle_license_types enable row level security;
alter table public.vehicle_license_requirements enable row level security;
alter table public.vehicle_licenses enable row level security;
alter table public.inspection_types enable row level security;
alter table public.vehicle_inspection_requirements enable row level security;
alter table public.vehicle_inspections enable row level security;
alter table public.vehicle_inspection_schedules enable row level security;
alter table public.vehicle_inspection_deficiencies enable row level security;
alter table public.vehicle_documents enable row level security;
alter table public.fleet_notification_history enable row level security;

grant select, insert, update, delete on public.vehicle_types, public.vehicle_statuses,
  public.vehicle_license_types, public.inspection_types to authenticated;
grant select, insert, update, delete on public.vehicles, public.vehicle_license_requirements,
  public.vehicle_licenses, public.vehicle_inspection_requirements, public.vehicle_inspections,
  public.vehicle_inspection_schedules, public.vehicle_inspection_deficiencies,
  public.vehicle_documents to authenticated;
grant select on public.fleet_notification_history to authenticated;

create policy vehicle_types_read on public.vehicle_types
for select to authenticated using (true);
create policy vehicle_types_admin_write on public.vehicle_types
for all to authenticated using ((select private.is_system_admin()))
with check ((select private.is_system_admin()));

create policy vehicle_statuses_read on public.vehicle_statuses
for select to authenticated using (true);
create policy vehicle_statuses_admin_write on public.vehicle_statuses
for all to authenticated using ((select private.is_system_admin()))
with check ((select private.is_system_admin()));

create policy vehicles_read on public.vehicles
for select to authenticated
using ((select private.has_agency_access(agency_id)));

create policy vehicles_insert on public.vehicles
for insert to authenticated
with check ((select private.can_manage_agency_fleet(agency_id)));

create policy vehicles_update on public.vehicles
for update to authenticated
using ((select private.can_manage_agency_fleet(agency_id)))
with check ((select private.can_manage_agency_fleet(agency_id)));

create policy vehicles_delete on public.vehicles
for delete to authenticated using ((select private.is_system_admin()));

create policy vehicle_license_types_read on public.vehicle_license_types
for select to authenticated using (true);
create policy vehicle_license_types_admin_write on public.vehicle_license_types
for all to authenticated using ((select private.is_system_admin()))
with check ((select private.is_system_admin()));

create policy vehicle_license_requirements_read on public.vehicle_license_requirements
for select to authenticated
using (
  (select private.is_system_admin())
  or scope_type = 'system'
  or (scope_type = 'agency' and (select private.has_agency_access(agency_id)))
);
create policy vehicle_license_requirements_admin_write on public.vehicle_license_requirements
for all to authenticated using ((select private.is_system_admin()))
with check ((select private.is_system_admin()));

create policy vehicle_licenses_read on public.vehicle_licenses
for select to authenticated using ((select private.can_view_vehicle(vehicle_id)));
create policy vehicle_licenses_insert on public.vehicle_licenses
for insert to authenticated with check ((select private.can_manage_vehicle(vehicle_id)));
create policy vehicle_licenses_update on public.vehicle_licenses
for update to authenticated
using ((select private.can_manage_vehicle(vehicle_id)))
with check ((select private.can_manage_vehicle(vehicle_id)));
create policy vehicle_licenses_delete on public.vehicle_licenses
for delete to authenticated using ((select private.is_system_admin()));

create policy inspection_types_read on public.inspection_types
for select to authenticated using (true);
create policy inspection_types_admin_write on public.inspection_types
for all to authenticated using ((select private.is_system_admin()))
with check ((select private.is_system_admin()));

create policy vehicle_inspection_requirements_read on public.vehicle_inspection_requirements
for select to authenticated
using (
  (select private.is_system_admin())
  or scope_type = 'system'
  or (scope_type = 'agency' and (select private.has_agency_access(agency_id)))
);
create policy vehicle_inspection_requirements_admin_write on public.vehicle_inspection_requirements
for all to authenticated using ((select private.is_system_admin()))
with check ((select private.is_system_admin()));

create policy vehicle_inspections_read on public.vehicle_inspections
for select to authenticated using ((select private.can_view_vehicle(vehicle_id)));
create policy vehicle_inspections_insert on public.vehicle_inspections
for insert to authenticated with check ((select private.can_manage_vehicle(vehicle_id)));
create policy vehicle_inspections_update on public.vehicle_inspections
for update to authenticated
using ((select private.can_manage_vehicle(vehicle_id)))
with check ((select private.can_manage_vehicle(vehicle_id)));
create policy vehicle_inspections_delete on public.vehicle_inspections
for delete to authenticated using ((select private.is_system_admin()));

create policy vehicle_inspection_schedules_read on public.vehicle_inspection_schedules
for select to authenticated using ((select private.can_view_vehicle(vehicle_id)));
create policy vehicle_inspection_schedules_insert on public.vehicle_inspection_schedules
for insert to authenticated with check ((select private.can_manage_vehicle(vehicle_id)));
create policy vehicle_inspection_schedules_update on public.vehicle_inspection_schedules
for update to authenticated
using ((select private.can_manage_vehicle(vehicle_id)))
with check ((select private.can_manage_vehicle(vehicle_id)));
create policy vehicle_inspection_schedules_delete on public.vehicle_inspection_schedules
for delete to authenticated using ((select private.is_system_admin()));

create policy vehicle_inspection_deficiencies_read on public.vehicle_inspection_deficiencies
for select to authenticated
using (
  exists (
    select 1
    from public.vehicle_inspections vi
    where vi.id = vehicle_inspection_deficiencies.vehicle_inspection_id
      and (select private.can_view_vehicle(vi.vehicle_id))
  )
);
create policy vehicle_inspection_deficiencies_insert on public.vehicle_inspection_deficiencies
for insert to authenticated
with check (
  exists (
    select 1
    from public.vehicle_inspections vi
    where vi.id = vehicle_inspection_deficiencies.vehicle_inspection_id
      and (select private.can_manage_vehicle(vi.vehicle_id))
  )
);
create policy vehicle_inspection_deficiencies_update on public.vehicle_inspection_deficiencies
for update to authenticated
using (
  exists (
    select 1
    from public.vehicle_inspections vi
    where vi.id = vehicle_inspection_deficiencies.vehicle_inspection_id
      and (select private.can_manage_vehicle(vi.vehicle_id))
  )
)
with check (
  exists (
    select 1
    from public.vehicle_inspections vi
    where vi.id = vehicle_inspection_deficiencies.vehicle_inspection_id
      and (select private.can_manage_vehicle(vi.vehicle_id))
  )
);
create policy vehicle_inspection_deficiencies_delete on public.vehicle_inspection_deficiencies
for delete to authenticated using ((select private.is_system_admin()));

create policy vehicle_documents_read on public.vehicle_documents
for select to authenticated
using (
  (vehicle_license_id is not null and exists (
    select 1 from public.vehicle_licenses vl
    where vl.id = vehicle_documents.vehicle_license_id
      and (select private.can_view_vehicle(vl.vehicle_id))
  ))
  or
  (vehicle_inspection_id is not null and exists (
    select 1 from public.vehicle_inspections vi
    where vi.id = vehicle_documents.vehicle_inspection_id
      and (select private.can_view_vehicle(vi.vehicle_id))
  ))
  or
  (deficiency_id is not null and exists (
    select 1
    from public.vehicle_inspection_deficiencies vd
    join public.vehicle_inspections vi on vi.id = vd.vehicle_inspection_id
    where vd.id = vehicle_documents.deficiency_id
      and (select private.can_view_vehicle(vi.vehicle_id))
  ))
);

create policy vehicle_documents_insert on public.vehicle_documents
for insert to authenticated
with check (
  uploaded_by = (select auth.uid())
  and (
    (vehicle_license_id is not null and exists (
      select 1 from public.vehicle_licenses vl
      where vl.id = vehicle_documents.vehicle_license_id
        and (select private.can_manage_vehicle(vl.vehicle_id))
    ))
    or
    (vehicle_inspection_id is not null and exists (
      select 1 from public.vehicle_inspections vi
      where vi.id = vehicle_documents.vehicle_inspection_id
        and (select private.can_manage_vehicle(vi.vehicle_id))
    ))
    or
    (deficiency_id is not null and exists (
      select 1
      from public.vehicle_inspection_deficiencies vd
      join public.vehicle_inspections vi on vi.id = vd.vehicle_inspection_id
      where vd.id = vehicle_documents.deficiency_id
        and (select private.can_manage_vehicle(vi.vehicle_id))
    ))
  )
);

create policy vehicle_documents_delete on public.vehicle_documents
for delete to authenticated
using (
  (select private.is_system_admin())
  or
  (vehicle_license_id is not null and exists (
    select 1 from public.vehicle_licenses vl
    where vl.id = vehicle_documents.vehicle_license_id
      and (select private.can_manage_vehicle(vl.vehicle_id))
  ))
  or
  (vehicle_inspection_id is not null and exists (
    select 1 from public.vehicle_inspections vi
    where vi.id = vehicle_documents.vehicle_inspection_id
      and (select private.can_manage_vehicle(vi.vehicle_id))
  ))
  or
  (deficiency_id is not null and exists (
    select 1
    from public.vehicle_inspection_deficiencies vd
    join public.vehicle_inspections vi on vi.id = vd.vehicle_inspection_id
    where vd.id = vehicle_documents.deficiency_id
      and (select private.can_manage_vehicle(vi.vehicle_id))
  ))
);

create policy fleet_notification_history_read on public.fleet_notification_history
for select to authenticated
using ((select private.has_agency_access(agency_id)));

-- -----------------------------------------------------------------------------
-- Security-invoker fleet views for dashboards and reports
-- -----------------------------------------------------------------------------

create or replace view public.current_vehicle_licenses
with (security_invoker = true)
as
select
  vl.id,
  vl.vehicle_id,
  v.agency_id,
  vl.vehicle_license_type_id,
  vlt.code as license_code,
  vlt.name as license_name,
  vlt.category,
  vl.license_number,
  vl.issue_date,
  vl.expiration_date,
  case
    when vl.expiration_date is null then 'CURRENT'
    when vl.expiration_date < current_date then 'EXPIRED'
    when vl.expiration_date <= current_date + coalesce((select max(d) from unnest(vlt.warning_days) d), 90)
      then 'EXPIRING_SOON'
    else 'CURRENT'
  end as status,
  case when vl.expiration_date is null then null else (vl.expiration_date - current_date) end as days_remaining,
  vl.verified_by,
  vl.verified_at,
  vl.source,
  vl.updated_at
from public.vehicle_licenses vl
join public.vehicles v on v.id = vl.vehicle_id
join public.vehicle_license_types vlt on vlt.id = vl.vehicle_license_type_id
where vl.is_current = true
  and vl.verification_status = 'verified';

grant select on public.current_vehicle_licenses to authenticated;

create or replace view public.vehicle_license_compliance
with (security_invoker = true)
as
with required_pairs as (
  select distinct v.id as vehicle_id, r.vehicle_license_type_id
  from public.vehicles v
  join public.vehicle_statuses vs on vs.id = v.vehicle_status_id
  join public.vehicle_license_requirements r
    on r.scope_type = 'system'
   and r.required = true
   and (r.vehicle_type_id is null or r.vehicle_type_id = v.vehicle_type_id)
   and (r.effective_start_date is null or r.effective_start_date <= current_date)
   and (r.effective_end_date is null or r.effective_end_date >= current_date)
  where v.active = true and vs.counts_toward_compliance = true

  union

  select distinct v.id as vehicle_id, r.vehicle_license_type_id
  from public.vehicles v
  join public.vehicle_statuses vs on vs.id = v.vehicle_status_id
  join public.vehicle_license_requirements r
    on r.scope_type = 'agency'
   and r.agency_id = v.agency_id
   and r.required = true
   and (r.vehicle_type_id is null or r.vehicle_type_id = v.vehicle_type_id)
   and (r.effective_start_date is null or r.effective_start_date <= current_date)
   and (r.effective_end_date is null or r.effective_end_date >= current_date)
  where v.active = true and vs.counts_toward_compliance = true
)
select
  rp.vehicle_id,
  v.agency_id,
  v.unit_number,
  v.vin,
  rp.vehicle_license_type_id,
  vlt.code as license_code,
  vlt.name as license_name,
  vl.id as vehicle_license_id,
  vl.expiration_date,
  case
    when vl.id is null then 'MISSING'
    when vl.expiration_date is not null and vl.expiration_date < current_date then 'EXPIRED'
    when vl.expiration_date is not null
      and vl.expiration_date <= current_date + coalesce((select max(d) from unnest(vlt.warning_days) d), 90)
      then 'EXPIRING_SOON'
    else 'CURRENT'
  end as compliance_status,
  case when vl.expiration_date is null then null else (vl.expiration_date - current_date) end as days_remaining
from required_pairs rp
join public.vehicles v on v.id = rp.vehicle_id
join public.vehicle_license_types vlt on vlt.id = rp.vehicle_license_type_id
left join public.vehicle_licenses vl
  on vl.vehicle_id = rp.vehicle_id
 and vl.vehicle_license_type_id = rp.vehicle_license_type_id
 and vl.is_current = true
 and vl.verification_status = 'verified';

grant select on public.vehicle_license_compliance to authenticated;

create or replace view public.vehicle_inspection_compliance
with (security_invoker = true)
as
with required_pairs as (
  select distinct v.id as vehicle_id, r.inspection_type_id
  from public.vehicles v
  join public.vehicle_statuses vs on vs.id = v.vehicle_status_id
  join public.vehicle_inspection_requirements r
    on r.scope_type = 'system'
   and r.required = true
   and (r.vehicle_type_id is null or r.vehicle_type_id = v.vehicle_type_id)
   and (r.effective_start_date is null or r.effective_start_date <= current_date)
   and (r.effective_end_date is null or r.effective_end_date >= current_date)
  where v.active = true and vs.counts_toward_compliance = true

  union

  select distinct v.id as vehicle_id, r.inspection_type_id
  from public.vehicles v
  join public.vehicle_statuses vs on vs.id = v.vehicle_status_id
  join public.vehicle_inspection_requirements r
    on r.scope_type = 'agency'
   and r.agency_id = v.agency_id
   and r.required = true
   and (r.vehicle_type_id is null or r.vehicle_type_id = v.vehicle_type_id)
   and (r.effective_start_date is null or r.effective_start_date <= current_date)
   and (r.effective_end_date is null or r.effective_end_date >= current_date)
  where v.active = true and vs.counts_toward_compliance = true
)
select
  rp.vehicle_id,
  v.agency_id,
  v.unit_number,
  v.vin,
  rp.inspection_type_id,
  it.code as inspection_code,
  it.name as inspection_name,
  lis.id as latest_inspection_id,
  lis.inspection_date as latest_inspection_date,
  lis.result as latest_result,
  s.next_due_date,
  case
    when lis.result in ('failed', 'out_of_service') then 'FAILED'
    when s.id is null and lis.id is null then 'MISSING'
    when s.id is null then 'SCHEDULE_MISSING'
    when s.next_due_date < current_date then 'OVERDUE'
    when s.next_due_date <= current_date + coalesce((select max(d) from unnest(it.warning_days) d), 30)
      then 'DUE_SOON'
    else 'CURRENT'
  end as compliance_status,
  case when s.next_due_date is null then null else (s.next_due_date - current_date) end as days_until_due
from required_pairs rp
join public.vehicles v on v.id = rp.vehicle_id
join public.inspection_types it on it.id = rp.inspection_type_id
left join public.vehicle_inspection_schedules s
  on s.vehicle_id = rp.vehicle_id
 and s.inspection_type_id = rp.inspection_type_id
 and s.active = true
left join lateral (
  select vi.*
  from public.vehicle_inspections vi
  where vi.vehicle_id = rp.vehicle_id
    and vi.inspection_type_id = rp.inspection_type_id
  order by vi.inspection_date desc, vi.created_at desc
  limit 1
) lis on true;

grant select on public.vehicle_inspection_compliance to authenticated;

-- -----------------------------------------------------------------------------
-- Fleet seed values. These are intentionally generic; regulatory license and
-- inspection definitions should be configured by System Administration.
-- -----------------------------------------------------------------------------

insert into public.vehicle_types(code, name, sort_order)
values
  ('AMBULANCE', 'Ambulance', 10),
  ('RESPONSE', 'Response Vehicle', 20),
  ('SUPERVISOR', 'Supervisor Vehicle', 30),
  ('SUPPORT', 'Support Vehicle', 40)
on conflict (code) do nothing;

insert into public.vehicle_statuses(code, name, counts_toward_compliance, sort_order)
values
  ('ACTIVE', 'Active', true, 10),
  ('RESERVE', 'Reserve', true, 20),
  ('OUT_OF_SERVICE', 'Out of Service', true, 30),
  ('RETIRED', 'Retired', false, 90),
  ('SOLD', 'Sold / Disposed', false, 100)
on conflict (code) do nothing;

insert into public.vehicle_license_types(
  code, name, category, requires_number, requires_issue_date,
  requires_expiration_date, requires_document
)
values
  ('EMS_VEHICLE_LICENSE', 'EMS Vehicle License', 'EMS License', true, false, true, false),
  ('VEHICLE_REGISTRATION', 'Vehicle Registration', 'Registration', true, false, true, false)
on conflict (code) do nothing;

insert into public.inspection_types(
  code, name, description, default_interval_months, requires_document, tracks_deficiencies
)
values
  ('EMS_REGULATORY_INSPECTION', 'EMS Regulatory Inspection', 'Configurable regulatory inspection record.', null, true, true),
  ('AGENCY_VEHICLE_INSPECTION', 'Agency Vehicle Inspection', 'Configurable agency inspection record.', null, false, true)
on conflict (code) do nothing;

commit;
