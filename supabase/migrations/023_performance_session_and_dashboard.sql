-- GEAEMS Portal v0.11.0
-- Performance: cheaper RLS helpers, administrator fast-path policies,
-- a single session-context RPC, a single dashboard-summary RPC, and
-- a few supporting indexes.
--
-- Run after migrations 001 through 022. Safe to re-run.
--
-- Nothing in this migration grants access that a user did not already have:
--   * the fast-path policies only short-circuit evaluation for users who
--     already pass the existing policies (System Administrators, and agency
--     access that the existing has_agency_access() helper already allowed);
--   * the two RPCs return only the caller's own context, or counts of rows the
--     caller can already read through the existing row-level security.

begin;

-- -----------------------------------------------------------------------------
-- 1. Cheaper role helpers (same semantics, fewer lookups per call)
-- -----------------------------------------------------------------------------

-- Previously is_system_admin() ran two queries (profiles + user_roles) and was
-- invoked from inside has_agency_access(), can_view_vehicle(), etc. for every
-- row. One indexed join is enough.
create or replace function private.is_system_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.profiles p
    join public.user_roles ur on ur.user_id = p.id
    where p.id = (select auth.uid())
      and p.active = true
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
  select exists (
    select 1
    from public.profiles p
    where p.id = (select auth.uid())
      and p.active = true
      and (
        exists (
          select 1 from public.user_roles ur
          where ur.user_id = p.id and ur.role = 'system_admin'
        )
        or exists (
          select 1 from public.user_agency_access uaa
          where uaa.user_id = p.id and uaa.agency_id = p_agency_id
        )
      )
  );
$$;

-- Set of agency ids the current active user may access. Because it takes no
-- arguments, a policy written as `agency_id in (select private.user_agency_ids())`
-- is planned as a one-time init plan (hashed set) instead of a per-row function
-- call chain.
create or replace function private.user_agency_ids()
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select uaa.agency_id
  from public.user_agency_access uaa
  join public.profiles p on p.id = uaa.user_id
  where uaa.user_id = (select auth.uid())
    and p.active = true;
$$;

revoke execute on function private.is_system_admin() from public, anon;
revoke execute on function private.has_agency_access(uuid) from public, anon;
revoke execute on function private.user_agency_ids() from public, anon;
grant execute on function private.is_system_admin() to authenticated;
grant execute on function private.has_agency_access(uuid) to authenticated;
grant execute on function private.user_agency_ids() to authenticated;

-- -----------------------------------------------------------------------------
-- 2. Administrator fast-path SELECT policies
--
-- Postgres ORs permissive policies together, in policy-name order. A policy
-- whose expression is `(select private.is_system_admin())` contains no column
-- reference, so it is evaluated ONCE per statement as an init plan. For a
-- System Administrator the OR short-circuits before the expensive per-row
-- helper (can_view_vehicle_inspection(id), can_view_provider(id), ...) runs.
-- The leading underscore makes these sort before every existing policy name.
-- -----------------------------------------------------------------------------

do $$
declare
  t text;
begin
  foreach t in array array[
    'agencies', 'providers', 'provider_agencies', 'provider_credentials',
    'credential_submissions', 'credential_documents', 'credential_requirements',
    'credential_types', 'notification_history',
    'vehicles', 'vehicle_licenses', 'vehicle_documents',
    'vehicle_inspections', 'vehicle_inspection_schedules', 'vehicle_inspection_deficiencies',
    'vehicle_inspection_requirements', 'vehicle_license_requirements', 'fleet_notification_history',
    'inspection_form_templates', 'inspection_form_versions', 'inspection_form_sections',
    'inspection_form_items', 'inspection_item_responses',
    'narcotics_count_templates', 'narcotics_count_template_items', 'narcotics_agency_settings',
    'narcotics_counts', 'narcotics_count_lines', 'narcotics_report_history',
    'ce_courses', 'ce_sessions', 'ce_session_instructors', 'ce_attendance', 'ce_external_submissions',
    'record_field_definitions', 'record_custom_field_values',
    'saved_reports', 'report_schedule_runs',
    'user_roles', 'user_agency_access', 'profiles'
  ] loop
    if to_regclass('public.' || t) is not null then
      execute format('drop policy if exists "_fast_system_admin_read" on public.%I', t);
      execute format(
        'create policy "_fast_system_admin_read" on public.%I for select to authenticated using ((select private.is_system_admin()))',
        t
      );
    end if;
  end loop;
end $$;

-- Agency-scoped fast paths for the two hottest tables. Equivalent to the
-- existing has_agency_access() branch of agencies_read / vehicles_read, but
-- evaluated as a hashed init plan instead of a per-row function chain.
drop policy if exists "_fast_agency_access_read" on public.agencies;
create policy "_fast_agency_access_read" on public.agencies
for select to authenticated
using (id in (select private.user_agency_ids()));

drop policy if exists "_fast_agency_access_read" on public.vehicles;
create policy "_fast_agency_access_read" on public.vehicles
for select to authenticated
using (agency_id in (select private.user_agency_ids()));

-- -----------------------------------------------------------------------------
-- 3. Supporting indexes
-- -----------------------------------------------------------------------------

create index if not exists vehicles_active_agency_idx
  on public.vehicles(active, agency_id);

create index if not exists vehicle_inspections_created_idx
  on public.vehicle_inspections(created_at desc);

create index if not exists vehicle_inspections_vehicle_status_idx
  on public.vehicle_inspections(vehicle_id, workflow_status);

create index if not exists vehicle_inspection_deficiencies_open_idx
  on public.vehicle_inspection_deficiencies(vehicle_inspection_id)
  where status = 'open';

create index if not exists agencies_active_idx
  on public.agencies(active);

create index if not exists provider_agencies_provider_active_idx
  on public.provider_agencies(provider_id, agency_id)
  where active = true;

create index if not exists credential_submissions_pending_idx
  on public.credential_submissions(provider_id)
  where status = 'pending';

-- -----------------------------------------------------------------------------
-- 4. Session context RPC — one round trip for everything the portal needs to
--    authorize a request (replaces 3–6 queries per page in proxy + layout).
-- -----------------------------------------------------------------------------

create or replace function public.get_session_context()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with me as (
    select u.id, u.email
    from auth.users u
    where u.id = (select auth.uid())
  ),
  prof as (
    select p.id, p.active, p.provider_id, p.display_name
    from public.profiles p
    where p.id = (select auth.uid())
  )
  select jsonb_build_object(
    'user_id', me.id,
    'email', me.email,
    'profile_exists', prof.id is not null,
    'active', coalesce(prof.active, false),
    'provider_id', prof.provider_id,
    'display_name', prof.display_name,
    'roles', coalesce((
      select jsonb_agg(ur.role order by ur.role)
      from public.user_roles ur
      where ur.user_id = me.id
    ), '[]'::jsonb),
    'agency_access', coalesce((
      select jsonb_agg(jsonb_build_object(
        'agency_id', uaa.agency_id,
        'can_manage_personnel', uaa.can_manage_personnel,
        'can_manage_credentials', uaa.can_manage_credentials,
        'can_manage_fleet', uaa.can_manage_fleet,
        'can_manage_narcotics', coalesce(uaa.can_manage_narcotics, false)
      ))
      from public.user_agency_access uaa
      where uaa.user_id = me.id
    ), '[]'::jsonb),
    'modules', coalesce((
      select jsonb_object_agg(sms.module_key, sms.enabled)
      from public.system_module_settings sms
    ), '{}'::jsonb)
  )
  from me
  left join prof on prof.id = me.id;
$$;

revoke execute on function public.get_session_context() from public, anon;
grant execute on function public.get_session_context() to authenticated;

-- -----------------------------------------------------------------------------
-- 5. Dashboard summary RPC — replaces ~17 count queries with one call.
--    SECURITY INVOKER: every count is computed through the caller's own
--    row-level security, exactly as the individual queries were.
-- -----------------------------------------------------------------------------

create or replace function public.dashboard_summary()
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_modules jsonb;
  v_personnel boolean;
  v_credentials boolean;
  v_fleet boolean;
  v_inspections boolean;
  v_narcotics boolean;
  v_result jsonb := '{}'::jsonb;
  v_narcotics_missing jsonb := '[]'::jsonb;
begin
  select coalesce(jsonb_object_agg(module_key, enabled), '{}'::jsonb)
    into v_modules
  from public.system_module_settings;

  v_personnel   := coalesce((v_modules->>'personnel')::boolean, false);
  v_credentials := coalesce((v_modules->>'credentials')::boolean, false);
  v_fleet       := coalesce((v_modules->>'fleet')::boolean, true);
  v_inspections := coalesce((v_modules->>'inspections')::boolean, true);
  v_narcotics   := coalesce((v_modules->>'narcotics')::boolean, false);

  v_result := jsonb_build_object(
    'agencies', (select count(*) from public.agencies a where a.active = true),
    'providers', case when v_personnel then (select count(*) from public.providers) else 0 end,
    'pending_submissions', case when v_credentials then (select count(*) from public.credential_submissions where status = 'pending') else 0 end,
    'credentials_expired', case when v_credentials then (select count(*) from public.provider_compliance where compliance_status = 'EXPIRED') else 0 end,
    'credentials_expiring', case when v_credentials then (select count(*) from public.provider_compliance where compliance_status = 'EXPIRING_SOON') else 0 end,
    'credentials_missing', case when v_credentials then (select count(*) from public.provider_compliance where compliance_status = 'MISSING') else 0 end,
    'vehicles', case when v_fleet then (
      select count(*) from public.vehicles v
      join public.agencies a on a.id = v.agency_id and a.active = true
      where v.active = true
    ) else 0 end,
    'inspections_overdue', case when v_inspections then (
      select count(*) from public.vehicle_inspection_compliance c
      join public.agencies a on a.id = c.agency_id and a.active = true
      where c.compliance_status = 'OVERDUE') else 0 end,
    'inspections_due_soon', case when v_inspections then (
      select count(*) from public.vehicle_inspection_compliance c
      join public.agencies a on a.id = c.agency_id and a.active = true
      where c.compliance_status = 'DUE_SOON') else 0 end,
    'inspections_failed', case when v_inspections then (
      select count(*) from public.vehicle_inspection_compliance c
      join public.agencies a on a.id = c.agency_id and a.active = true
      where c.compliance_status = 'FAILED') else 0 end,
    'inspections_missing', case when v_inspections then (
      select count(*) from public.vehicle_inspection_compliance c
      join public.agencies a on a.id = c.agency_id and a.active = true
      where c.compliance_status in ('MISSING', 'SCHEDULE_MISSING')) else 0 end,
    'deficiencies_open', case when v_inspections then (
      select count(*) from public.vehicle_inspection_deficiencies d
      join public.vehicle_inspections vi on vi.id = d.vehicle_inspection_id
      join public.vehicles v on v.id = vi.vehicle_id and v.active = true
      join public.agencies a on a.id = v.agency_id and a.active = true
      where d.status = 'open') else 0 end,
    'deficiencies_critical', case when v_inspections then (
      select count(*) from public.vehicle_inspection_deficiencies d
      join public.vehicle_inspections vi on vi.id = d.vehicle_inspection_id
      join public.vehicles v on v.id = vi.vehicle_id and v.active = true
      join public.agencies a on a.id = v.agency_id and a.active = true
      where d.status = 'open' and d.severity = 'critical') else 0 end,
    'licenses_expiring', case when v_fleet then (
      select count(*) from public.vehicle_license_compliance c
      join public.agencies a on a.id = c.agency_id and a.active = true
      where c.compliance_status = 'EXPIRING_SOON') else 0 end,
    'licenses_expired', case when v_fleet then (
      select count(*) from public.vehicle_license_compliance c
      join public.agencies a on a.id = c.agency_id and a.active = true
      where c.compliance_status = 'EXPIRED') else 0 end,
    'licenses_missing', case when v_fleet then (
      select count(*) from public.vehicle_license_compliance c
      join public.agencies a on a.id = c.agency_id and a.active = true
      where c.compliance_status = 'MISSING') else 0 end
  );

  if v_narcotics then
    -- Apparatus that require a signed daily count and have no submitted count
    -- for "today" in the agency's configured time zone.
    select coalesce(jsonb_agg(jsonb_build_object(
        'vehicle_id', x.vehicle_id,
        'agency', x.agency_label,
        'unit', x.unit_label,
        'state', x.state
      ) order by x.agency_label, x.unit_label), '[]'::jsonb)
      into v_narcotics_missing
    from (
      select
        v.id as vehicle_id,
        coalesce(a.short_name, a.name, 'Agency') as agency_label,
        coalesce(v.unit_number, v.fleet_number, 'Unnumbered') as unit_label,
        case
          when vt.narcotics_template_id is null then 'no form configured'
          when exists (
            select 1 from public.narcotics_counts nc
            where nc.vehicle_id = v.id
              and nc.count_date = (now() at time zone coalesce(s.timezone, 'America/Chicago'))::date
              and nc.status = 'draft'
          ) then 'draft not submitted'
          else 'not started'
        end as state
      from public.vehicles v
      join public.agencies a on a.id = v.agency_id and a.active = true
      left join public.vehicle_types vt on vt.id = v.vehicle_type_id
      left join public.narcotics_agency_settings s on s.agency_id = v.agency_id
      where v.active = true
        and v.narcotics_count_required = true
        and coalesce(s.enabled, true)
        and not exists (
          select 1 from public.narcotics_counts nc
          where nc.vehicle_id = v.id
            and nc.count_date = (now() at time zone coalesce(s.timezone, 'America/Chicago'))::date
            and nc.status = 'submitted'
        )
    ) x;
  end if;

  return v_result || jsonb_build_object('modules', v_modules, 'narcotics_missing', v_narcotics_missing);
end;
$$;

revoke execute on function public.dashboard_summary() from public, anon;
grant execute on function public.dashboard_summary() to authenticated;

commit;

notify pgrst, 'reload schema';
