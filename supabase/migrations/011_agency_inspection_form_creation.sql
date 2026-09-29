-- GEAEMS Portal v0.6.3
-- Adds a transactional Agency Inspection Form creation RPC.
-- Run after migrations 001 through 010.

begin;

-- A generic inspection category keeps agency-owned forms distinct from the
-- official GEAEMS System equipment inspection in history and reporting.
insert into public.inspection_types(
  code, name, description, default_interval_months, requires_document,
  tracks_deficiencies, warning_days, active
)
values (
  'AGENCY_VEHICLE_INSPECTION',
  'Agency Vehicle Inspection',
  'Agency-owned digital vehicle inspection checklist.',
  null, false, true, array[30,14,7,1], true
)
on conflict (code) do update
set name = excluded.name,
    description = excluded.description,
    active = true;

create or replace function public.create_agency_inspection_form(
  p_agency_id uuid,
  p_vehicle_type_id uuid,
  p_name text,
  p_description text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_template_id uuid;
  v_inspection_type_id uuid;
  v_code text;
begin
  if auth.uid() is null or not private.is_user_active() then
    raise exception 'Authentication is required';
  end if;

  if p_agency_id is null or p_vehicle_type_id is null then
    raise exception 'Agency and vehicle type are required';
  end if;

  if coalesce(btrim(p_name), '') = '' then
    raise exception 'Inspection form name is required';
  end if;

  if not (
    private.is_system_admin()
    or private.can_manage_agency_fleet(p_agency_id)
  ) then
    raise exception 'You do not have permission to create inspection forms for this agency';
  end if;

  if not exists (
    select 1 from public.agencies a
    where a.id = p_agency_id and a.active
  ) then
    raise exception 'Agency was not found or is inactive';
  end if;

  if not exists (
    select 1 from public.vehicle_types vt
    where vt.id = p_vehicle_type_id and vt.active
  ) then
    raise exception 'Vehicle type was not found or is inactive';
  end if;

  -- One active agency checklist per agency + vehicle profile keeps the Start
  -- Inspection workflow deterministic. Existing forms can be edited/versioned.
  if exists (
    select 1
    from public.inspection_form_templates t
    where t.scope_type = 'agency'
      and t.agency_id = p_agency_id
      and t.vehicle_type_id = p_vehicle_type_id
      and t.active
  ) then
    raise exception 'An active agency inspection form already exists for this vehicle type. Edit the existing form instead.';
  end if;

  select id into v_inspection_type_id
  from public.inspection_types
  where code = 'AGENCY_VEHICLE_INSPECTION'
  limit 1;

  if v_inspection_type_id is null then
    raise exception 'Agency Vehicle Inspection type is not configured';
  end if;

  v_code := 'AGENCY_' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 20));

  insert into public.inspection_form_templates(
    code, name, description, inspection_type_id, vehicle_type_id,
    scope_type, agency_id, active, created_by
  ) values (
    v_code,
    btrim(p_name),
    nullif(btrim(coalesce(p_description, '')), ''),
    v_inspection_type_id,
    p_vehicle_type_id,
    'agency',
    p_agency_id,
    true,
    auth.uid()
  ) returning id into v_template_id;

  insert into public.inspection_form_versions(
    template_id, version_number, status, source_name
  ) values (
    v_template_id, 1, 'draft', 'Portal form editor'
  );

  return v_template_id;
end;
$$;

revoke execute on function public.create_agency_inspection_form(uuid, uuid, text, text) from public, anon;
grant execute on function public.create_agency_inspection_form(uuid, uuid, text, text) to authenticated;

commit;
