-- GEAEMS Portal v0.9
-- Continuing education tracking: scheduled courses/sessions, provider check-in,
-- session completion codes, manual roster entry, external/online CE certificates,
-- transcript data, and CE-specific roles.
-- Run after migrations 001 through 016.

begin;

-- -----------------------------------------------------------------------------
-- Roles
-- -----------------------------------------------------------------------------

alter table public.user_roles
  drop constraint if exists user_roles_role_check;

alter table public.user_roles
  add constraint user_roles_role_check
  check (role in (
    'system_admin',
    'system_inspector',
    'agency_admin',
    'ce_coordinator',
    'ce_instructor',
    'provider'
  ));

create or replace function private.is_ce_coordinator()
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
        select 1 from public.user_roles ur
        where ur.user_id = (select auth.uid())
          and ur.role = 'ce_coordinator'
      )
    );
$$;

create or replace function private.is_ce_instructor()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.is_user_active()
    and exists (
      select 1 from public.user_roles ur
      where ur.user_id = (select auth.uid())
        and ur.role = 'ce_instructor'
    );
$$;

revoke execute on function private.is_ce_coordinator() from public, anon;
revoke execute on function private.is_ce_instructor() from public, anon;
grant execute on function private.is_ce_coordinator() to authenticated;
grant execute on function private.is_ce_instructor() to authenticated;

-- -----------------------------------------------------------------------------
-- Course catalog and scheduled offerings
-- -----------------------------------------------------------------------------

create table if not exists public.ce_courses (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  course_code text,
  description text,
  category text,
  credit_hours numeric(6,2) not null default 1 check (credit_hours >= 0),
  active boolean not null default true,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists ce_courses_title_idx on public.ce_courses(title);
create index if not exists ce_courses_active_idx on public.ce_courses(active);

create table if not exists public.ce_sessions (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references public.ce_courses(id) on delete cascade,
  start_at timestamptz not null,
  end_at timestamptz not null,
  location_name text,
  location_address text,
  timezone text not null default 'America/Chicago',
  capacity integer check (capacity is null or capacity > 0),
  credit_hours_override numeric(6,2) check (credit_hours_override is null or credit_hours_override >= 0),
  self_checkin_enabled boolean not null default true,
  check_in_open_minutes integer not null default 60 check (check_in_open_minutes between 0 and 1440),
  verification_close_hours integer not null default 24 check (verification_close_hours between 1 and 168),
  verification_code_generated_at timestamptz,
  status text not null default 'scheduled' check (status in ('scheduled','cancelled','completed')),
  notes text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ce_sessions_time_check check (end_at > start_at)
);

create index if not exists ce_sessions_course_idx on public.ce_sessions(course_id);
create index if not exists ce_sessions_start_idx on public.ce_sessions(start_at);
create index if not exists ce_sessions_status_idx on public.ce_sessions(status);

create table if not exists public.ce_session_instructors (
  session_id uuid not null references public.ce_sessions(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  assigned_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  primary key (session_id, user_id)
);

create index if not exists ce_session_instructors_user_idx on public.ce_session_instructors(user_id);

-- Completion code is deliberately separated from ce_sessions so providers can
-- read a session without ever being able to select the secret value.
create table if not exists public.ce_session_secrets (
  session_id uuid primary key references public.ce_sessions(id) on delete cascade,
  verification_code text not null,
  generated_by uuid references auth.users(id) on delete set null,
  generated_at timestamptz not null default now()
);

create table if not exists public.ce_attendance (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.ce_sessions(id) on delete cascade,
  provider_id uuid not null references public.providers(id) on delete cascade,
  status text not null default 'checked_in' check (status in ('checked_in','completed','absent')),
  source text not null default 'self' check (source in ('self','manual')),
  checked_in_at timestamptz,
  verified_at timestamptz,
  verification_method text check (verification_method is null or verification_method in ('code','manual')),
  credit_hours_awarded numeric(6,2) check (credit_hours_awarded is null or credit_hours_awarded >= 0),
  entered_by uuid references auth.users(id) on delete set null,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (session_id, provider_id)
);

create index if not exists ce_attendance_provider_idx on public.ce_attendance(provider_id);
create index if not exists ce_attendance_session_idx on public.ce_attendance(session_id);
create index if not exists ce_attendance_status_idx on public.ce_attendance(status);

-- -----------------------------------------------------------------------------
-- External / online CE submissions
-- -----------------------------------------------------------------------------

create table if not exists public.ce_external_submissions (
  id uuid primary key default gen_random_uuid(),
  provider_id uuid not null references public.providers(id) on delete cascade,
  title text not null,
  sponsor text,
  category text,
  completion_date date not null,
  credit_hours numeric(6,2) not null check (credit_hours >= 0),
  certificate_path text,
  certificate_filename text,
  notes text,
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  submitted_by uuid not null references auth.users(id) on delete cascade,
  submitted_at timestamptz not null default now(),
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  review_notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists ce_external_provider_idx on public.ce_external_submissions(provider_id);
create index if not exists ce_external_status_idx on public.ce_external_submissions(status);
create index if not exists ce_external_completion_idx on public.ce_external_submissions(completion_date);

-- -----------------------------------------------------------------------------
-- Authorization helpers
-- -----------------------------------------------------------------------------

create or replace function private.can_manage_ce_session(p_session_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.is_user_active()
    and (
      private.is_ce_coordinator()
      or exists (
        select 1 from public.ce_session_instructors csi
        where csi.session_id = p_session_id
          and csi.user_id = (select auth.uid())
      )
    );
$$;

create or replace function private.can_view_ce_attendance(p_session_id uuid, p_provider_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.is_user_active()
    and (
      p_provider_id = private.my_provider_id()
      or private.can_manage_ce_session(p_session_id)
      or private.can_view_provider(p_provider_id)
    );
$$;

revoke execute on function private.can_manage_ce_session(uuid) from public, anon;
revoke execute on function private.can_view_ce_attendance(uuid, uuid) from public, anon;
grant execute on function private.can_manage_ce_session(uuid) to authenticated;
grant execute on function private.can_view_ce_attendance(uuid, uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- RLS
-- -----------------------------------------------------------------------------

alter table public.ce_courses enable row level security;
alter table public.ce_sessions enable row level security;
alter table public.ce_session_instructors enable row level security;
alter table public.ce_session_secrets enable row level security;
alter table public.ce_attendance enable row level security;
alter table public.ce_external_submissions enable row level security;

create policy ce_courses_read on public.ce_courses
for select to authenticated
using ((select private.is_user_active()));

create policy ce_courses_insert on public.ce_courses
for insert to authenticated
with check ((select private.is_ce_coordinator()));

create policy ce_courses_update on public.ce_courses
for update to authenticated
using ((select private.is_ce_coordinator()))
with check ((select private.is_ce_coordinator()));

create policy ce_sessions_read on public.ce_sessions
for select to authenticated
using ((select private.is_user_active()));

create policy ce_sessions_insert on public.ce_sessions
for insert to authenticated
with check ((select private.is_ce_coordinator()));

create policy ce_sessions_update on public.ce_sessions
for update to authenticated
using ((select private.is_ce_coordinator()))
with check ((select private.is_ce_coordinator()));

create policy ce_session_instructors_read on public.ce_session_instructors
for select to authenticated
using (
  (select private.is_ce_coordinator())
  or user_id = (select auth.uid())
  or (select private.can_manage_ce_session(session_id))
);

create policy ce_session_instructors_write on public.ce_session_instructors
for all to authenticated
using ((select private.is_ce_coordinator()))
with check ((select private.is_ce_coordinator()));

create policy ce_session_secrets_read on public.ce_session_secrets
for select to authenticated
using ((select private.can_manage_ce_session(session_id)));


create policy ce_attendance_read on public.ce_attendance
for select to authenticated
using ((select private.can_view_ce_attendance(session_id, provider_id)));


create policy ce_external_read on public.ce_external_submissions
for select to authenticated
using (
  (select private.is_user_active())
  and (
    provider_id = (select private.my_provider_id())
    or (select private.is_ce_coordinator())
    or (select private.can_view_provider(provider_id))
  )
);

create policy ce_external_insert on public.ce_external_submissions
for insert to authenticated
with check (
  provider_id = (select private.my_provider_id())
  and submitted_by = (select auth.uid())
  and status = 'pending'
);

create policy ce_external_provider_update on public.ce_external_submissions
for update to authenticated
using (
  provider_id = (select private.my_provider_id())
  and submitted_by = (select auth.uid())
  and status = 'pending'
)
with check (
  provider_id = (select private.my_provider_id())
  and submitted_by = (select auth.uid())
  and status = 'pending'
);


create policy ce_external_delete on public.ce_external_submissions
for delete to authenticated
using (
  (
    provider_id = (select private.my_provider_id())
    and submitted_by = (select auth.uid())
    and status = 'pending'
  )
  or (select private.is_ce_coordinator())
);

-- -----------------------------------------------------------------------------
-- Secure external CE certificate storage
-- Object path: <provider_uuid>/<submission_uuid>/<filename>
-- -----------------------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'ce-certificates',
  'ce-certificates',
  false,
  10485760,
  array['application/pdf','image/jpeg','image/png','image/webp']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create or replace function private.ce_storage_submission_id(p_name text)
returns uuid
language plpgsql
immutable
security definer
set search_path = ''
as $$
begin
  if split_part(p_name, '/', 2) = '' then return null; end if;
  return split_part(p_name, '/', 2)::uuid;
exception when others then
  return null;
end;
$$;

create or replace function private.can_read_ce_storage_object(p_name text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_submission_id uuid;
  v_provider_id uuid;
begin
  v_submission_id := private.ce_storage_submission_id(p_name);
  if v_submission_id is null then return false; end if;

  select provider_id into v_provider_id
  from public.ce_external_submissions
  where id = v_submission_id;

  if v_provider_id is null then return false; end if;
  return private.is_ce_coordinator() or v_provider_id = private.my_provider_id();
end;
$$;

create or replace function private.can_write_ce_storage_object(p_name text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_submission_id uuid;
  v_provider_id uuid;
  v_status text;
  v_submitted_by uuid;
begin
  v_submission_id := private.ce_storage_submission_id(p_name);
  if v_submission_id is null then return false; end if;

  select provider_id, status, submitted_by
    into v_provider_id, v_status, v_submitted_by
  from public.ce_external_submissions
  where id = v_submission_id;

  if v_provider_id is null then return false; end if;
  return (
    v_provider_id = private.my_provider_id()
    and v_submitted_by = auth.uid()
    and v_status = 'pending'
    and split_part(p_name, '/', 1) = v_provider_id::text
  ) or private.is_ce_coordinator();
end;
$$;

revoke execute on function private.ce_storage_submission_id(text) from public, anon;
revoke execute on function private.can_read_ce_storage_object(text) from public, anon;
revoke execute on function private.can_write_ce_storage_object(text) from public, anon;
grant execute on function private.ce_storage_submission_id(text) to authenticated;
grant execute on function private.can_read_ce_storage_object(text) to authenticated;
grant execute on function private.can_write_ce_storage_object(text) to authenticated;

drop policy if exists geaems_ce_certificates_select on storage.objects;
drop policy if exists geaems_ce_certificates_insert on storage.objects;
drop policy if exists geaems_ce_certificates_update on storage.objects;
drop policy if exists geaems_ce_certificates_delete on storage.objects;

create policy geaems_ce_certificates_select on storage.objects
for select to authenticated
using (
  bucket_id = 'ce-certificates'
  and (select private.can_read_ce_storage_object(name))
);

create policy geaems_ce_certificates_insert on storage.objects
for insert to authenticated
with check (
  bucket_id = 'ce-certificates'
  and (select private.can_write_ce_storage_object(name))
);

create policy geaems_ce_certificates_update on storage.objects
for update to authenticated
using (
  bucket_id = 'ce-certificates'
  and (select private.can_write_ce_storage_object(name))
)
with check (
  bucket_id = 'ce-certificates'
  and (select private.can_write_ce_storage_object(name))
);

create policy geaems_ce_certificates_delete on storage.objects
for delete to authenticated
using (
  bucket_id = 'ce-certificates'
  and (select private.can_write_ce_storage_object(name))
);

-- -----------------------------------------------------------------------------
-- Provider self check-in and completion verification
-- -----------------------------------------------------------------------------

create or replace function public.ce_self_check_in(p_session_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_provider_id uuid;
  v_session public.ce_sessions%rowtype;
  v_id uuid;
begin
  if not private.is_user_active() then raise exception 'Active portal account required'; end if;
  v_provider_id := private.my_provider_id();
  if v_provider_id is null then raise exception 'A linked provider record is required'; end if;

  select * into v_session from public.ce_sessions where id = p_session_id;
  if not found then raise exception 'CE session not found'; end if;
  if v_session.status <> 'scheduled' then raise exception 'This CE session is not open for attendance'; end if;
  if not v_session.self_checkin_enabled then raise exception 'Self check-in is disabled for this session'; end if;
  if now() < v_session.start_at - make_interval(mins => v_session.check_in_open_minutes) then
    raise exception 'Check-in is not open yet';
  end if;
  if now() > v_session.end_at then raise exception 'Self check-in has closed'; end if;
  if v_session.capacity is not null
     and not exists (select 1 from public.ce_attendance where session_id = p_session_id and provider_id = v_provider_id)
     and (select count(*) from public.ce_attendance where session_id = p_session_id and status <> 'absent') >= v_session.capacity then
    raise exception 'This CE session has reached capacity';
  end if;

  insert into public.ce_attendance (
    session_id, provider_id, status, source, checked_in_at, entered_by
  ) values (
    p_session_id, v_provider_id, 'checked_in', 'self', now(), auth.uid()
  )
  on conflict (session_id, provider_id) do update
    set checked_in_at = coalesce(public.ce_attendance.checked_in_at, excluded.checked_in_at),
        updated_at = now()
  returning id into v_id;

  return v_id;
end;
$$;

create or replace function public.ce_verify_attendance(p_session_id uuid, p_code text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_provider_id uuid;
  v_session public.ce_sessions%rowtype;
  v_course public.ce_courses%rowtype;
  v_secret text;
  v_id uuid;
begin
  if not private.is_user_active() then raise exception 'Active portal account required'; end if;
  v_provider_id := private.my_provider_id();
  if v_provider_id is null then raise exception 'A linked provider record is required'; end if;

  select * into v_session from public.ce_sessions where id = p_session_id;
  if not found then raise exception 'CE session not found'; end if;
  if v_session.status = 'cancelled' then raise exception 'This CE session was cancelled'; end if;
  if v_session.verification_code_generated_at is null then raise exception 'The completion code has not been released yet'; end if;
  if now() > v_session.end_at + make_interval(hours => v_session.verification_close_hours) then
    raise exception 'The attendance verification window has closed';
  end if;

  select verification_code into v_secret
  from public.ce_session_secrets where session_id = p_session_id;
  if v_secret is null or upper(btrim(coalesce(p_code,''))) <> upper(v_secret) then
    raise exception 'Invalid completion code';
  end if;

  select * into v_course from public.ce_courses where id = v_session.course_id;

  update public.ce_attendance
  set status = 'completed',
      verified_at = now(),
      verification_method = 'code',
      credit_hours_awarded = coalesce(v_session.credit_hours_override, v_course.credit_hours),
      updated_at = now()
  where session_id = p_session_id
    and provider_id = v_provider_id
    and checked_in_at is not null
  returning id into v_id;

  if v_id is null then raise exception 'You must check in before verifying completion'; end if;
  return v_id;
end;
$$;

create or replace function public.ce_generate_verification_code(p_session_id uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_code text;
begin
  if not private.can_manage_ce_session(p_session_id) then
    raise exception 'You are not authorized to manage this CE session';
  end if;

  select verification_code into v_code
  from public.ce_session_secrets
  where session_id = p_session_id;

  if v_code is null then
    v_code := upper(substr(encode(extensions.gen_random_bytes(8), 'hex'), 1, 6));
    insert into public.ce_session_secrets(session_id, verification_code, generated_by, generated_at)
    values (p_session_id, v_code, auth.uid(), now())
    on conflict (session_id) do nothing;

    select verification_code into v_code
    from public.ce_session_secrets where session_id = p_session_id;
  end if;

  update public.ce_sessions
  set verification_code_generated_at = coalesce(verification_code_generated_at, now()),
      updated_at = now()
  where id = p_session_id;

  return v_code;
end;
$$;

create or replace function public.ce_manual_mark_attendance(
  p_session_id uuid,
  p_provider_id uuid,
  p_completed boolean default true,
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_session public.ce_sessions%rowtype;
  v_course public.ce_courses%rowtype;
  v_id uuid;
begin
  if not private.can_manage_ce_session(p_session_id) then
    raise exception 'You are not authorized to manage this CE session';
  end if;

  select * into v_session from public.ce_sessions where id = p_session_id;
  if not found then raise exception 'CE session not found'; end if;
  select * into v_course from public.ce_courses where id = v_session.course_id;
  if not exists (select 1 from public.providers where id = p_provider_id) then
    raise exception 'Provider not found';
  end if;

  insert into public.ce_attendance (
    session_id, provider_id, status, source, checked_in_at, verified_at,
    verification_method, credit_hours_awarded, entered_by, notes
  ) values (
    p_session_id,
    p_provider_id,
    case when p_completed then 'completed' else 'checked_in' end,
    'manual',
    now(),
    case when p_completed then now() else null end,
    case when p_completed then 'manual' else null end,
    case when p_completed then coalesce(v_session.credit_hours_override, v_course.credit_hours) else null end,
    auth.uid(),
    nullif(btrim(coalesce(p_notes,'')), '')
  )
  on conflict (session_id, provider_id) do update
    set status = excluded.status,
        source = 'manual',
        checked_in_at = coalesce(public.ce_attendance.checked_in_at, excluded.checked_in_at),
        verified_at = case when p_completed then now() else public.ce_attendance.verified_at end,
        verification_method = case when p_completed then 'manual' else public.ce_attendance.verification_method end,
        credit_hours_awarded = case when p_completed then coalesce(v_session.credit_hours_override, v_course.credit_hours) else public.ce_attendance.credit_hours_awarded end,
        entered_by = auth.uid(),
        notes = coalesce(nullif(btrim(coalesce(p_notes,'')), ''), public.ce_attendance.notes),
        updated_at = now()
  returning id into v_id;

  return v_id;
end;
$$;

revoke execute on function public.ce_self_check_in(uuid) from public, anon;
revoke execute on function public.ce_verify_attendance(uuid, text) from public, anon;
revoke execute on function public.ce_generate_verification_code(uuid) from public, anon;
revoke execute on function public.ce_manual_mark_attendance(uuid, uuid, boolean, text) from public, anon;
grant execute on function public.ce_self_check_in(uuid) to authenticated;
grant execute on function public.ce_verify_attendance(uuid, text) to authenticated;
grant execute on function public.ce_generate_verification_code(uuid) to authenticated;
grant execute on function public.ce_manual_mark_attendance(uuid, uuid, boolean, text) to authenticated;

-- -----------------------------------------------------------------------------
-- Limited directories for roster entry and instructor assignment
-- -----------------------------------------------------------------------------

create or replace function public.ce_provider_directory(p_session_id uuid)
returns table (
  provider_id uuid,
  provider_name text,
  provider_number text,
  agency_name text
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    p.id,
    concat_ws(', ', p.last_name, p.first_name),
    p.provider_number,
    coalesce((
      select coalesce(a.short_name, a.name)
      from public.provider_agencies pa
      join public.agencies a on a.id = pa.agency_id
      where pa.provider_id = p.id and pa.active = true
      order by pa.is_primary desc, a.name
      limit 1
    ), '')
  from public.providers p
  where private.can_manage_ce_session(p_session_id)
  order by p.last_name, p.first_name;
$$;

create or replace function public.ce_instructor_directory()
returns table (
  user_id uuid,
  display_name text,
  provider_id uuid
)
language sql
stable
security definer
set search_path = ''
as $$
  select p.id, coalesce(nullif(p.display_name,''), au.email, 'Instructor'), p.provider_id
  from public.profiles p
  join auth.users au on au.id = p.id
  where private.is_ce_coordinator()
    and p.active = true
    and exists (
      select 1 from public.user_roles ur
      where ur.user_id = p.id and ur.role = 'ce_instructor'
    )
  order by coalesce(nullif(p.display_name,''), au.email, 'Instructor');
$$;

revoke execute on function public.ce_provider_directory(uuid) from public, anon;
revoke execute on function public.ce_instructor_directory() from public, anon;
grant execute on function public.ce_provider_directory(uuid) to authenticated;
grant execute on function public.ce_instructor_directory() to authenticated;

-- -----------------------------------------------------------------------------
-- External CE review directory
-- -----------------------------------------------------------------------------

create or replace function public.ce_external_review_queue(p_status text default 'pending')
returns table (
  id uuid,
  provider_id uuid,
  provider_name text,
  provider_number text,
  title text,
  sponsor text,
  category text,
  completion_date date,
  credit_hours numeric,
  certificate_path text,
  certificate_filename text,
  notes text,
  status text,
  submitted_at timestamptz,
  reviewed_at timestamptz,
  review_notes text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not private.is_ce_coordinator() then
    raise exception 'CE Coordinator access is required';
  end if;
  if p_status not in ('pending','approved','rejected','all') then
    raise exception 'Invalid CE review status';
  end if;

  return query
  select
    ces.id,
    ces.provider_id,
    concat_ws(', ', p.last_name, p.first_name),
    p.provider_number,
    ces.title,
    ces.sponsor,
    ces.category,
    ces.completion_date,
    ces.credit_hours,
    ces.certificate_path,
    ces.certificate_filename,
    ces.notes,
    ces.status,
    ces.submitted_at,
    ces.reviewed_at,
    ces.review_notes
  from public.ce_external_submissions ces
  join public.providers p on p.id = ces.provider_id
  where p_status = 'all' or ces.status = p_status
  order by case when ces.status = 'pending' then 0 else 1 end, ces.submitted_at asc;
end;
$$;

revoke execute on function public.ce_external_review_queue(text) from public, anon;
grant execute on function public.ce_external_review_queue(text) to authenticated;

-- -----------------------------------------------------------------------------
-- External CE review RPC
-- -----------------------------------------------------------------------------

create or replace function public.review_external_ce(
  p_submission_id uuid,
  p_decision text,
  p_notes text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not private.is_ce_coordinator() then
    raise exception 'CE Coordinator access is required';
  end if;
  if p_decision not in ('approved','rejected') then
    raise exception 'Decision must be approved or rejected';
  end if;

  update public.ce_external_submissions
  set status = p_decision,
      reviewed_by = auth.uid(),
      reviewed_at = now(),
      review_notes = nullif(btrim(coalesce(p_notes,'')), ''),
      updated_at = now()
  where id = p_submission_id;

  if not found then raise exception 'External CE submission not found'; end if;
end;
$$;

revoke execute on function public.review_external_ce(uuid, text, text) from public, anon;
grant execute on function public.review_external_ce(uuid, text, text) to authenticated;

commit;

NOTIFY pgrst, 'reload schema';
