-- GEAEMS Portal v0.7.0
-- Custom report builder, saved report definitions, and scheduled email delivery.
-- Run after migrations 001 through 014.

begin;

create table if not exists public.saved_reports (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references auth.users(id) on delete cascade default auth.uid(),
  name text not null,
  description text,
  data_source text not null check (data_source in (
    'personnel',
    'agencies',
    'credential_compliance',
    'credential_records',
    'credential_history',
    'credential_submissions',
    'credential_type_census',
    'fleet',
    'vehicle_license_compliance',
    'inspection_compliance',
    'inspection_history',
    'inspection_deficiencies',
    'narcotics_history',
    'agency_compliance_summary'
  )),
  selected_columns jsonb not null default '[]'::jsonb,
  filters jsonb not null default '[]'::jsonb,
  sort_field text,
  sort_direction text not null default 'asc' check (sort_direction in ('asc','desc')),
  group_field text,

  schedule_enabled boolean not null default false,
  schedule_frequency text check (schedule_frequency is null or schedule_frequency in ('daily','weekly','monthly')),
  schedule_timezone text not null default 'America/Chicago',
  schedule_hour smallint not null default 8 check (schedule_hour between 0 and 23),
  schedule_weekday smallint check (schedule_weekday is null or schedule_weekday between 0 and 6),
  schedule_day_of_month smallint check (schedule_day_of_month is null or schedule_day_of_month between 1 and 31),
  schedule_recipients text[] not null default '{}',
  schedule_delivery_mode text not null default 'inline_csv' check (schedule_delivery_mode in ('inline','csv','inline_csv')),
  last_run_at timestamptz,
  last_run_status text check (last_run_status is null or last_run_status in ('sent','failed','skipped')),
  last_run_message text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint saved_reports_columns_array check (jsonb_typeof(selected_columns) = 'array'),
  constraint saved_reports_filters_array check (jsonb_typeof(filters) = 'array'),
  constraint saved_reports_recipient_limit check (cardinality(schedule_recipients) <= 25),
  constraint saved_reports_schedule_configuration check (
    schedule_enabled = false
    or (
      schedule_frequency is not null
      and cardinality(schedule_recipients) > 0
      and (schedule_frequency <> 'weekly' or schedule_weekday is not null)
      and (schedule_frequency <> 'monthly' or schedule_day_of_month is not null)
    )
  )
);

create index if not exists saved_reports_owner_idx
  on public.saved_reports(owner_user_id, updated_at desc);
create index if not exists saved_reports_schedule_idx
  on public.saved_reports(schedule_enabled, schedule_frequency)
  where schedule_enabled = true;

drop trigger if exists set_saved_reports_updated_at on public.saved_reports;
create trigger set_saved_reports_updated_at
before update on public.saved_reports
for each row execute function private.set_updated_at();

create table if not exists public.report_schedule_runs (
  id bigint generated always as identity primary key,
  saved_report_id uuid not null references public.saved_reports(id) on delete cascade,
  run_key text not null,
  scheduled_local_date date not null,
  status text not null check (status in ('sent','failed','skipped')),
  recipient_count integer not null default 0 check (recipient_count >= 0),
  recipients text[] not null default '{}',
  row_count integer not null default 0 check (row_count >= 0),
  provider_message_id text,
  error_message text,
  created_at timestamptz not null default now(),
  unique(saved_report_id, run_key)
);

create index if not exists report_schedule_runs_report_idx
  on public.report_schedule_runs(saved_report_id, created_at desc);

alter table public.saved_reports enable row level security;
alter table public.report_schedule_runs enable row level security;

grant select, insert, update, delete on public.saved_reports to authenticated;
grant select on public.report_schedule_runs to authenticated;
grant select, insert, update, delete on public.saved_reports to service_role;
grant select, insert, update, delete on public.report_schedule_runs to service_role;

drop policy if exists saved_reports_read on public.saved_reports;
create policy saved_reports_read on public.saved_reports
for select to authenticated
using (
  owner_user_id = (select auth.uid())
  or (select private.is_system_admin())
);

drop policy if exists saved_reports_insert on public.saved_reports;
create policy saved_reports_insert on public.saved_reports
for insert to authenticated
with check (
  owner_user_id = (select auth.uid())
  and (
    (select private.is_system_admin())
    or (select private.is_agency_admin())
  )
);

drop policy if exists saved_reports_update on public.saved_reports;
create policy saved_reports_update on public.saved_reports
for update to authenticated
using (
  owner_user_id = (select auth.uid())
  or (select private.is_system_admin())
)
with check (
  owner_user_id = (select auth.uid())
  or (select private.is_system_admin())
);

drop policy if exists saved_reports_delete on public.saved_reports;
create policy saved_reports_delete on public.saved_reports
for delete to authenticated
using (
  owner_user_id = (select auth.uid())
  or (select private.is_system_admin())
);

drop policy if exists report_schedule_runs_read on public.report_schedule_runs;
create policy report_schedule_runs_read on public.report_schedule_runs
for select to authenticated
using (
  exists (
    select 1
    from public.saved_reports sr
    where sr.id = report_schedule_runs.saved_report_id
      and (
        sr.owner_user_id = (select auth.uid())
        or (select private.is_system_admin())
      )
  )
);

notify pgrst, 'reload schema';

commit;
