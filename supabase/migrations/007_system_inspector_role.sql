-- GEAEMS Portal v0.5.2
-- Adds the System Inspector role and limits GEAEMS System inspection performance
-- to System Inspectors and System Administrators.
-- Run after migrations 001 through 006.

begin;

-- -----------------------------------------------------------------------------
-- Role definition
-- -----------------------------------------------------------------------------

alter table public.user_roles
  drop constraint if exists user_roles_role_check;

alter table public.user_roles
  add constraint user_roles_role_check
  check (role in ('system_admin', 'system_inspector', 'agency_admin', 'provider'));

create or replace function private.is_system_inspector()
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
        and ur.role = 'system_inspector'
    );
$$;

revoke execute on function private.is_system_inspector() from public, anon;
grant execute on function private.is_system_inspector() to authenticated;

-- -----------------------------------------------------------------------------
-- Inspection authorization helpers
-- -----------------------------------------------------------------------------

-- True when the current user is allowed to perform the supplied form on the
-- supplied vehicle. System forms are restricted to System Admin + System
-- Inspector. Agency forms remain available to the agency's Fleet administrators.
create or replace function private.can_perform_inspection_form(
  p_vehicle_id uuid,
  p_form_version_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.is_user_active()
    and exists (
      select 1
      from public.vehicles veh
      join public.inspection_form_versions fv
        on fv.id = p_form_version_id
      join public.inspection_form_templates t
        on t.id = fv.template_id
      where veh.id = p_vehicle_id
        and veh.vehicle_type_id = t.vehicle_type_id
        and veh.active = true
        and fv.status = 'published'
        and t.active = true
        and (
          private.is_system_admin()
          or (
            private.is_system_inspector()
            and t.scope_type = 'system'
          )
          or (
            t.scope_type = 'agency'
            and t.agency_id = veh.agency_id
            and private.can_manage_agency_fleet(veh.agency_id)
          )
        )
    );
$$;

create or replace function private.can_edit_vehicle_inspection(p_inspection_id uuid)
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
      where vi.id = p_inspection_id
        and vi.workflow_status = 'draft'
        and vi.form_version_id is not null
        and private.can_perform_inspection_form(vi.vehicle_id, vi.form_version_id)
    );
$$;

-- System Inspectors can review GEAEMS System inspections across the System.
-- Agency administrators continue to see inspection history for vehicles they
-- already have agency access to.
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
      where vi.id = p_inspection_id
        and (
          private.is_system_admin()
          or private.can_view_vehicle(vi.vehicle_id)
          or (
            private.is_system_inspector()
            and t.scope_type = 'system'
          )
        )
    );
$$;

revoke execute on function private.can_perform_inspection_form(uuid, uuid) from public, anon;
revoke execute on function private.can_edit_vehicle_inspection(uuid) from public, anon;
revoke execute on function private.can_view_vehicle_inspection(uuid) from public, anon;
grant execute on function private.can_perform_inspection_form(uuid, uuid) to authenticated;
grant execute on function private.can_edit_vehicle_inspection(uuid) to authenticated;
grant execute on function private.can_view_vehicle_inspection(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- Minimum read access required by a System Inspector
-- -----------------------------------------------------------------------------

-- They need agency labels and vehicle master information to identify the unit
-- being inspected, but this does not grant Fleet write privileges.
drop policy if exists agencies_read on public.agencies;
create policy agencies_read on public.agencies
for select to authenticated
using (
  (select private.is_system_admin())
  or (select private.is_system_inspector())
  or (select private.has_agency_access(id))
  or exists (
    select 1 from public.provider_agencies pa
    where pa.agency_id = agencies.id
      and pa.provider_id = (select private.my_provider_id())
      and pa.active = true
  )
);

drop policy if exists vehicles_read on public.vehicles;
create policy vehicles_read on public.vehicles
for select to authenticated
using (
  (select private.is_system_inspector())
  or (select private.has_agency_access(agency_id))
);

-- -----------------------------------------------------------------------------
-- Vehicle inspection records
-- -----------------------------------------------------------------------------

drop policy if exists vehicle_inspections_read on public.vehicle_inspections;
create policy vehicle_inspections_read on public.vehicle_inspections
for select to authenticated
using ((select private.can_view_vehicle_inspection(id)));

drop policy if exists vehicle_inspections_insert on public.vehicle_inspections;
create policy vehicle_inspections_insert on public.vehicle_inspections
for insert to authenticated
with check (
  form_version_id is not null
  and (select private.can_perform_inspection_form(vehicle_id, form_version_id))
);

drop policy if exists vehicle_inspections_update on public.vehicle_inspections;
create policy vehicle_inspections_update on public.vehicle_inspections
for update to authenticated
using (
  (select private.is_system_admin())
  or (select private.can_edit_vehicle_inspection(id))
)
with check (
  (select private.is_system_admin())
  or (
    workflow_status in ('draft','submitted')
    and form_version_id is not null
    and (select private.can_perform_inspection_form(vehicle_id, form_version_id))
  )
);

-- -----------------------------------------------------------------------------
-- Digital checklist answers
-- -----------------------------------------------------------------------------

drop policy if exists inspection_item_responses_read on public.inspection_item_responses;
create policy inspection_item_responses_read on public.inspection_item_responses
for select to authenticated
using ((select private.can_view_vehicle_inspection(vehicle_inspection_id)));

drop policy if exists inspection_item_responses_insert on public.inspection_item_responses;
create policy inspection_item_responses_insert on public.inspection_item_responses
for insert to authenticated
with check ((select private.can_edit_vehicle_inspection(vehicle_inspection_id)));

drop policy if exists inspection_item_responses_update on public.inspection_item_responses;
create policy inspection_item_responses_update on public.inspection_item_responses
for update to authenticated
using ((select private.can_edit_vehicle_inspection(vehicle_inspection_id)))
with check ((select private.can_edit_vehicle_inspection(vehicle_inspection_id)));

drop policy if exists inspection_item_responses_delete on public.inspection_item_responses;
create policy inspection_item_responses_delete on public.inspection_item_responses
for delete to authenticated
using ((select private.can_edit_vehicle_inspection(vehicle_inspection_id)));

-- -----------------------------------------------------------------------------
-- Deficiencies generated by system inspections
-- -----------------------------------------------------------------------------

drop policy if exists vehicle_inspection_deficiencies_read on public.vehicle_inspection_deficiencies;
create policy vehicle_inspection_deficiencies_read on public.vehicle_inspection_deficiencies
for select to authenticated
using ((select private.can_view_vehicle_inspection(vehicle_inspection_id)));

-- New deficiencies are generated while a draft is being submitted, so permit
-- the authorized inspector to insert them. Corrective-action edits remain under
-- the existing Fleet-management policy after submission.
drop policy if exists vehicle_inspection_deficiencies_insert on public.vehicle_inspection_deficiencies;
create policy vehicle_inspection_deficiencies_insert on public.vehicle_inspection_deficiencies
for insert to authenticated
with check ((select private.can_edit_vehicle_inspection(vehicle_inspection_id)));

commit;

NOTIFY pgrst, 'reload schema';
