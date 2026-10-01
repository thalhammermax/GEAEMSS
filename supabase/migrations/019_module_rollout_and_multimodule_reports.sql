-- GEAEMS Portal v0.10.0
-- Staged module rollout controls and multi-module report datasets.
-- Run after migrations 001 through 018.

begin;

create table if not exists public.system_module_settings (
  module_key text primary key check (module_key in (
    'personnel',
    'credentials',
    'ce',
    'fleet',
    'inspections',
    'narcotics',
    'reports'
  )),
  enabled boolean not null default false,
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now()
);

insert into public.system_module_settings(module_key, enabled)
values
  ('personnel', false),
  ('credentials', false),
  ('ce', false),
  ('fleet', true),
  ('inspections', true),
  ('narcotics', false),
  ('reports', true)
on conflict (module_key) do nothing;

alter table public.system_module_settings enable row level security;
grant select, insert, update on public.system_module_settings to authenticated;
grant select, insert, update, delete on public.system_module_settings to service_role;

drop policy if exists system_module_settings_read on public.system_module_settings;
drop policy if exists system_module_settings_insert on public.system_module_settings;
drop policy if exists system_module_settings_update on public.system_module_settings;

create policy system_module_settings_read
on public.system_module_settings
for select to authenticated
using ((select private.is_user_active()));

create policy system_module_settings_insert
on public.system_module_settings
for insert to authenticated
with check ((select private.is_system_admin()));

create policy system_module_settings_update
on public.system_module_settings
for update to authenticated
using ((select private.is_system_admin()))
with check ((select private.is_system_admin()));

-- v0.9 added CE report sources after the original v0.7 constraint was created.
-- v0.10 also adds safe composite datasets that combine related modules.
alter table public.saved_reports
  drop constraint if exists saved_reports_data_source_check;

alter table public.saved_reports
  add constraint saved_reports_data_source_check
  check (data_source in (
    'personnel',
    'agencies',
    'credential_compliance',
    'credential_records',
    'credential_history',
    'credential_submissions',
    'credential_type_census',
    'fleet',
    'vehicle_operations',
    'provider_operations',
    'vehicle_license_compliance',
    'inspection_compliance',
    'inspection_history',
    'inspection_deficiencies',
    'ce_completions',
    'ce_attendance_history',
    'narcotics_history',
    'agency_compliance_summary'
  ));

commit;

NOTIFY pgrst, 'reload schema';
