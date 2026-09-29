-- GEAEMS Portal v0.6.1
-- Adds version-safe inspection form editing and hides system inspection drafts
-- from anyone other than System Inspectors and System Administrators.
-- Run after migrations 001 through 008.

begin;

-- -----------------------------------------------------------------------------
-- Draft inspection privacy
-- -----------------------------------------------------------------------------

create or replace function private.can_view_vehicle_inspection(p_inspection_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.is_user_active()
    and exists (
      select 1
      from public.vehicle_inspections vi
      left join public.inspection_form_versions fv on fv.id = vi.form_version_id
      left join public.inspection_form_templates t on t.id = fv.template_id
      left join public.vehicles veh on veh.id = vi.vehicle_id
      where vi.id = p_inspection_id
        and (
          -- System Administration can recover/view any draft record.
          (
            vi.workflow_status = 'draft'
            and private.is_system_admin()
          )
          or
          -- GEAEMS System drafts are otherwise visible only to System Inspectors.
          -- Agency fleet administrators do not see an in-progress System inspection.
          (
            vi.workflow_status = 'draft'
            and t.scope_type = 'system'
            and private.is_system_inspector()
          )
          or
          -- Agency-owned drafts remain visible only to users authorized to
          -- perform that agency inspection plus System Administration.
          (
            vi.workflow_status = 'draft'
            and t.scope_type = 'agency'
            and (
              private.is_system_admin()
              or (
                t.agency_id = veh.agency_id
                and private.can_manage_agency_fleet(veh.agency_id)
              )
            )
          )
          or
          -- Submitted/void records retain the normal inspection-history access.
          (
            vi.workflow_status <> 'draft'
            and (
              private.is_system_admin()
              or private.can_view_vehicle(vi.vehicle_id)
              or (
                private.is_system_inspector()
                and t.scope_type = 'system'
              )
            )
          )
        )
    );
$$;

revoke execute on function private.can_view_vehicle_inspection(uuid) from public, anon;
grant execute on function private.can_view_vehicle_inspection(uuid) to authenticated;

-- The existing policies call private.can_view_vehicle_inspection(), so replacing
-- the helper above automatically tightens inspection, response and deficiency reads.

-- -----------------------------------------------------------------------------
-- Safe form-version editing
-- -----------------------------------------------------------------------------

create or replace function private.inspection_form_version_is_editable(p_version_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.is_user_active()
    and exists (
      select 1
      from public.inspection_form_versions v
      where v.id = p_version_id
        and v.status = 'draft'
        and private.can_manage_inspection_template(v.template_id)
    );
$$;

revoke execute on function private.inspection_form_version_is_editable(uuid) from public, anon;
grant execute on function private.inspection_form_version_is_editable(uuid) to authenticated;

-- Published checklist content is immutable. Editors work on a cloned draft
-- version, then publish that version when it is ready.
drop policy if exists inspection_form_sections_write on public.inspection_form_sections;
create policy inspection_form_sections_write on public.inspection_form_sections
for all to authenticated
using ((select private.inspection_form_version_is_editable(form_version_id)))
with check ((select private.inspection_form_version_is_editable(form_version_id)));

drop policy if exists inspection_form_items_write on public.inspection_form_items;
create policy inspection_form_items_write on public.inspection_form_items
for all to authenticated
using (
  exists (
    select 1
    from public.inspection_form_sections s
    where s.id = inspection_form_items.section_id
      and (select private.inspection_form_version_is_editable(s.form_version_id))
  )
)
with check (
  exists (
    select 1
    from public.inspection_form_sections s
    where s.id = inspection_form_items.section_id
      and (select private.inspection_form_version_is_editable(s.form_version_id))
  )
);

-- Split the former ALL policy so a published/retired version cannot be deleted.
drop policy if exists inspection_form_versions_write on public.inspection_form_versions;
drop policy if exists inspection_form_versions_insert on public.inspection_form_versions;
drop policy if exists inspection_form_versions_update on public.inspection_form_versions;
drop policy if exists inspection_form_versions_delete on public.inspection_form_versions;

create policy inspection_form_versions_insert on public.inspection_form_versions
for insert to authenticated
with check ((select private.can_manage_inspection_template(template_id)));

create policy inspection_form_versions_update on public.inspection_form_versions
for update to authenticated
using ((select private.can_manage_inspection_template(template_id)))
with check ((select private.can_manage_inspection_template(template_id)));

create policy inspection_form_versions_delete on public.inspection_form_versions
for delete to authenticated
using (
  status = 'draft'
  and (select private.can_manage_inspection_template(template_id))
);

create or replace function private.guard_inspection_form_version_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    if old.status <> 'draft' then
      raise exception 'Published and retired inspection form versions cannot be deleted';
    end if;
    return old;
  end if;

  if new.template_id is distinct from old.template_id
     or new.version_number is distinct from old.version_number then
    raise exception 'Inspection form version identity cannot be changed';
  end if;

  if old.status = 'published' and new.status not in ('published','retired') then
    raise exception 'Published inspection form versions can only remain published or be retired';
  end if;

  if old.status = 'retired' and new.status <> 'retired' then
    raise exception 'Retired inspection form versions cannot be reactivated';
  end if;

  if old.status = 'draft' and new.status not in ('draft','published') then
    raise exception 'Draft inspection form versions can only remain draft or be published';
  end if;

  return new;
end;
$$;

drop trigger if exists guard_inspection_form_version_change on public.inspection_form_versions;
create trigger guard_inspection_form_version_change
before update or delete on public.inspection_form_versions
for each row execute function private.guard_inspection_form_version_change();

-- Create (or return) one editable draft cloned from the current published form.
create or replace function public.create_inspection_form_draft(p_template_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_existing_draft uuid;
  v_source_version uuid;
  v_new_version uuid;
  v_next_version integer;
  v_source_section record;
  v_new_section uuid;
begin
  if not private.can_manage_inspection_template(p_template_id) then
    raise exception 'You do not have permission to edit this inspection form';
  end if;

  select id into v_existing_draft
  from public.inspection_form_versions
  where template_id = p_template_id and status = 'draft'
  order by version_number desc
  limit 1;

  if v_existing_draft is not null then
    return v_existing_draft;
  end if;

  select id into v_source_version
  from public.inspection_form_versions
  where template_id = p_template_id and status = 'published'
  order by version_number desc
  limit 1;

  if v_source_version is null then
    select id into v_source_version
    from public.inspection_form_versions
    where template_id = p_template_id and status = 'retired'
    order by version_number desc
    limit 1;
  end if;

  select coalesce(max(version_number), 0) + 1 into v_next_version
  from public.inspection_form_versions
  where template_id = p_template_id;

  insert into public.inspection_form_versions(
    template_id, version_number, status, source_name
  ) values (
    p_template_id, v_next_version, 'draft', 'Portal form editor'
  ) returning id into v_new_version;

  if v_source_version is not null then
    for v_source_section in
      select *
      from public.inspection_form_sections
      where form_version_id = v_source_version
      order by sort_order, created_at
    loop
      insert into public.inspection_form_sections(
        form_version_id, title, sort_order
      ) values (
        v_new_version, v_source_section.title, v_source_section.sort_order
      ) returning id into v_new_section;

      insert into public.inspection_form_items(
        section_id, item_code, label, requirement_text, response_type,
        required, allow_na, failure_severity, requires_comment_on_fail,
        source_row, sort_order
      )
      select
        v_new_section, item_code, label, requirement_text, response_type,
        required, allow_na, failure_severity, requires_comment_on_fail,
        source_row, sort_order
      from public.inspection_form_items
      where section_id = v_source_section.id
      order by sort_order, created_at;
    end loop;
  end if;

  return v_new_version;
end;
$$;

revoke execute on function public.create_inspection_form_draft(uuid) from public, anon;
grant execute on function public.create_inspection_form_draft(uuid) to authenticated;

-- Publish the edited draft atomically. The former published version becomes
-- retired but remains attached to historical inspections.
create or replace function public.publish_inspection_form_draft(p_version_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_template_id uuid;
  v_status text;
  v_item_count integer;
begin
  select template_id, status
  into v_template_id, v_status
  from public.inspection_form_versions
  where id = p_version_id;

  if v_template_id is null then
    raise exception 'Inspection form draft was not found';
  end if;

  if not private.can_manage_inspection_template(v_template_id) then
    raise exception 'You do not have permission to publish this inspection form';
  end if;

  if v_status <> 'draft' then
    raise exception 'Only a draft inspection form can be published';
  end if;

  select count(*) into v_item_count
  from public.inspection_form_items i
  join public.inspection_form_sections s on s.id = i.section_id
  where s.form_version_id = p_version_id;

  if v_item_count = 0 then
    raise exception 'Add at least one inspection item before publishing';
  end if;

  update public.inspection_form_versions
  set status = 'retired', updated_at = now()
  where template_id = v_template_id
    and status = 'published'
    and id <> p_version_id;

  update public.inspection_form_versions
  set status = 'published',
      published_at = now(),
      published_by = (select auth.uid()),
      updated_at = now()
  where id = p_version_id;

  return p_version_id;
end;
$$;

revoke execute on function public.publish_inspection_form_draft(uuid) from public, anon;
grant execute on function public.publish_inspection_form_draft(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- Support informational response types in editable forms.
-- -----------------------------------------------------------------------------

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
security invoker
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
