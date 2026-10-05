-- GEAEMS Portal
-- Fix digital inspection saves being blocked by RLS during the atomic
-- vehicle_inspections + responses + deficiencies transaction.
-- Run after migrations 001 through 019.

begin;

create or replace function public.save_digital_vehicle_inspection(
  p_inspection_id uuid,
  p_vehicle_id uuid,
  p_form_version_id uuid,
  p_inspection_date date,
  p_inspector_name text,
  p_inspector_organization text,
  p_inspection_location text,
  p_odometer integer,
  p_notes text,
  p_mode text,
  p_final_result text,
  p_responses jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_inspection_id uuid;
  v_inspection_type_id uuid;
  v_template_vehicle_type_id uuid;
  v_vehicle_type_id uuid;
  v_workflow text;
  v_required_count integer;
  v_answered_count integer;
  v_fail_count integer;
  v_result text;
begin
  if p_mode not in ('draft','submit') then
    raise exception 'Invalid inspection save mode';
  end if;

  if p_inspection_date is null then
    raise exception 'Inspection date is required';
  end if;

  select t.inspection_type_id, t.vehicle_type_id
  into v_inspection_type_id, v_template_vehicle_type_id
  from public.inspection_form_versions v
  join public.inspection_form_templates t on t.id = v.template_id
  where v.id = p_form_version_id
    and v.status = 'published'
    and t.active = true;

  if v_inspection_type_id is null then
    raise exception 'Published inspection form was not found';
  end if;

  select vehicle_type_id into v_vehicle_type_id
  from public.vehicles
  where id = p_vehicle_id;

  if v_vehicle_type_id is null then
    raise exception 'Vehicle was not found or has no inspection vehicle type';
  end if;

  if v_vehicle_type_id is distinct from v_template_vehicle_type_id then
    raise exception 'Inspection form does not match the selected vehicle type';
  end if;

  -- This RPC runs SECURITY DEFINER so the multi-table save can complete
  -- atomically without RLS blocking the draft -> submitted transition.
  -- Authorization is therefore enforced explicitly before any write occurs.
  if not private.can_perform_inspection_form(p_vehicle_id, p_form_version_id) then
    raise exception 'You are not authorized to perform this inspection form on the selected vehicle';
  end if;

  if p_inspection_id is null then
    insert into public.vehicle_inspections(
      vehicle_id, inspection_type_id, inspection_date, result, form_version_id,
      workflow_status, started_at, inspector_user_id, inspector_name,
      inspector_organization, inspection_location, odometer, notes
    ) values (
      p_vehicle_id, v_inspection_type_id, p_inspection_date, null, p_form_version_id,
      'draft', now(), (select auth.uid()), nullif(btrim(p_inspector_name),''),
      nullif(btrim(p_inspector_organization),''), nullif(btrim(p_inspection_location),''),
      p_odometer, nullif(btrim(p_notes),'')
    ) returning id into v_inspection_id;
  else
    select workflow_status into v_workflow
    from public.vehicle_inspections
    where id = p_inspection_id
      and vehicle_id = p_vehicle_id
      and form_version_id = p_form_version_id;

    if v_workflow is null then
      raise exception 'Inspection draft was not found';
    end if;
    if v_workflow <> 'draft' then
      raise exception 'Submitted inspections cannot be edited';
    end if;

    update public.vehicle_inspections
    set inspection_date = p_inspection_date,
        inspector_name = nullif(btrim(p_inspector_name),''),
        inspector_organization = nullif(btrim(p_inspector_organization),''),
        inspection_location = nullif(btrim(p_inspection_location),''),
        odometer = p_odometer,
        notes = nullif(btrim(p_notes),'')
    where id = p_inspection_id;
    v_inspection_id := p_inspection_id;
  end if;

  delete from public.inspection_item_responses
  where vehicle_inspection_id = v_inspection_id;

  insert into public.inspection_item_responses(
    vehicle_inspection_id, form_item_id, status, observed_value, notes
  )
  select
    v_inspection_id,
    r.form_item_id,
    nullif(r.status,''),
    nullif(btrim(r.observed_value),''),
    nullif(btrim(r.notes),'')
  from jsonb_to_recordset(coalesce(p_responses, '[]'::jsonb))
    as r(form_item_id uuid, status text, observed_value text, notes text)
  join public.inspection_form_items i on i.id = r.form_item_id
  join public.inspection_form_sections s on s.id = i.section_id
  where s.form_version_id = p_form_version_id
    and (
      r.status is not null
      or nullif(btrim(r.observed_value),'') is not null
      or nullif(btrim(r.notes),'') is not null
    );

  if p_mode = 'submit' then
    select count(*) into v_required_count
    from public.inspection_form_items i
    join public.inspection_form_sections s on s.id = i.section_id
    where s.form_version_id = p_form_version_id
      and i.required = true;

    select count(*) into v_answered_count
    from public.inspection_item_responses r
    join public.inspection_form_items i on i.id = r.form_item_id
    join public.inspection_form_sections s on s.id = i.section_id
    where r.vehicle_inspection_id = v_inspection_id
      and s.form_version_id = p_form_version_id
      and i.required = true
      and (
        (
          i.response_type = 'compliance'
          and r.status in ('pass','fail','na')
          and (r.status <> 'na' or i.allow_na = true)
        )
        or
        (
          i.response_type in ('text','number','date','yes_no')
          and nullif(btrim(r.observed_value),'') is not null
        )
      );

    if v_answered_count <> v_required_count then
      raise exception 'Every required inspection item must be completed before submission';
    end if;

    if exists (
      select 1
      from public.inspection_item_responses r
      join public.inspection_form_items i on i.id = r.form_item_id
      where r.vehicle_inspection_id = v_inspection_id
        and i.response_type = 'compliance'
        and r.status = 'fail'
        and i.requires_comment_on_fail = true
        and coalesce(btrim(r.notes),'') = ''
    ) then
      raise exception 'A comment is required for one or more deficient items';
    end if;

    select count(*) into v_fail_count
    from public.inspection_item_responses r
    join public.inspection_form_items i on i.id = r.form_item_id
    where r.vehicle_inspection_id = v_inspection_id
      and i.response_type = 'compliance'
      and r.status = 'fail';

    if v_fail_count = 0 then
      v_result := 'passed';
    else
      v_result := case
        when p_final_result in ('passed_with_deficiencies','failed','out_of_service') then p_final_result
        else 'passed_with_deficiencies'
      end;
    end if;

    delete from public.vehicle_inspection_deficiencies
    where vehicle_inspection_id = v_inspection_id
      and form_item_id is not null;

    insert into public.vehicle_inspection_deficiencies(
      vehicle_inspection_id, form_item_id, description, severity, status
    )
    select
      v_inspection_id,
      i.id,
      i.label || ' — Required: ' || i.requirement_text ||
        case when coalesce(btrim(r.notes),'') <> '' then ' — ' || btrim(r.notes) else '' end,
      i.failure_severity,
      'open'
    from public.inspection_item_responses r
    join public.inspection_form_items i on i.id = r.form_item_id
    where r.vehicle_inspection_id = v_inspection_id
      and i.response_type = 'compliance'
      and r.status = 'fail';

    update public.vehicle_inspections
    set workflow_status = 'submitted',
        result = v_result,
        submitted_at = now()
    where id = v_inspection_id;
  end if;

  return v_inspection_id;
end;
$$;

revoke execute on function public.save_digital_vehicle_inspection(
  uuid, uuid, uuid, date, text, text, text, integer, text, text, text, jsonb
) from public, anon;

grant execute on function public.save_digital_vehicle_inspection(
  uuid, uuid, uuid, date, text, text, text, integer, text, text, text, jsonb
) to authenticated;

commit;

NOTIFY pgrst, 'reload schema';
