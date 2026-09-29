-- GEAEMS Portal v0.5
-- Digital vehicle inspection forms derived from the GEA/IDPH EMS comparison matrix.
-- Run after migrations 001 through 005.

begin;

create table if not exists public.inspection_form_templates (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  description text,
  inspection_type_id uuid not null references public.inspection_types(id) on delete restrict,
  vehicle_type_id uuid not null references public.vehicle_types(id) on delete restrict,
  scope_type text not null default 'system' check (scope_type in ('system','agency')),
  agency_id uuid references public.agencies(id) on delete cascade,
  active boolean not null default true,
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint inspection_form_templates_scope_check check (
    (scope_type = 'system' and agency_id is null)
    or
    (scope_type = 'agency' and agency_id is not null)
  )
);

create index if not exists inspection_form_templates_vehicle_type_idx
  on public.inspection_form_templates(vehicle_type_id);
create index if not exists inspection_form_templates_agency_idx
  on public.inspection_form_templates(agency_id);

create table if not exists public.inspection_form_versions (
  id uuid primary key default gen_random_uuid(),
  template_id uuid not null references public.inspection_form_templates(id) on delete cascade,
  version_number integer not null check (version_number > 0),
  status text not null default 'draft' check (status in ('draft','published','retired')),
  source_name text,
  published_at timestamptz,
  published_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(template_id, version_number)
);

create index if not exists inspection_form_versions_template_idx
  on public.inspection_form_versions(template_id, version_number desc);

create table if not exists public.inspection_form_sections (
  id uuid primary key default gen_random_uuid(),
  form_version_id uuid not null references public.inspection_form_versions(id) on delete cascade,
  title text not null,
  sort_order integer not null default 100,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(form_version_id, sort_order)
);

create table if not exists public.inspection_form_items (
  id uuid primary key default gen_random_uuid(),
  section_id uuid not null references public.inspection_form_sections(id) on delete cascade,
  item_code text not null,
  label text not null,
  requirement_text text not null,
  response_type text not null default 'compliance' check (response_type in ('compliance','text','number','date','yes_no')),
  required boolean not null default true,
  allow_na boolean not null default false,
  failure_severity text not null default 'deficiency' check (failure_severity in ('advisory','deficiency','critical')),
  requires_comment_on_fail boolean not null default false,
  source_row integer,
  sort_order integer not null default 100,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(section_id, item_code)
);

create index if not exists inspection_form_items_section_idx
  on public.inspection_form_items(section_id, sort_order);

alter table public.vehicle_inspections alter column result drop not null;

alter table public.vehicle_inspections
  add column if not exists form_version_id uuid references public.inspection_form_versions(id) on delete restrict,
  add column if not exists workflow_status text not null default 'submitted'
    check (workflow_status in ('draft','submitted','void')),
  add column if not exists started_at timestamptz not null default now(),
  add column if not exists submitted_at timestamptz,
  add column if not exists inspector_user_id uuid references auth.users(id) on delete set null;

update public.vehicle_inspections
set workflow_status = 'submitted',
    submitted_at = coalesce(submitted_at, created_at)
where workflow_status = 'submitted' and submitted_at is null;

create index if not exists vehicle_inspections_workflow_idx
  on public.vehicle_inspections(workflow_status, inspection_date desc);
create index if not exists vehicle_inspections_form_version_idx
  on public.vehicle_inspections(form_version_id);

create table if not exists public.inspection_item_responses (
  id uuid primary key default gen_random_uuid(),
  vehicle_inspection_id uuid not null references public.vehicle_inspections(id) on delete cascade,
  form_item_id uuid not null references public.inspection_form_items(id) on delete restrict,
  status text check (status in ('pass','fail','na')),
  observed_value text,
  notes text,
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(vehicle_inspection_id, form_item_id)
);

create index if not exists inspection_item_responses_inspection_idx
  on public.inspection_item_responses(vehicle_inspection_id);
create index if not exists inspection_item_responses_failed_idx
  on public.inspection_item_responses(vehicle_inspection_id)
  where status = 'fail';

alter table public.vehicle_inspection_deficiencies
  add column if not exists form_item_id uuid references public.inspection_form_items(id) on delete set null;

create unique index if not exists vehicle_inspection_deficiencies_item_unique
  on public.vehicle_inspection_deficiencies(vehicle_inspection_id, form_item_id)
  where form_item_id is not null;

alter table public.inspection_form_templates enable row level security;
alter table public.inspection_form_versions enable row level security;
alter table public.inspection_form_sections enable row level security;
alter table public.inspection_form_items enable row level security;
alter table public.inspection_item_responses enable row level security;

grant select, insert, update, delete on
  public.inspection_form_templates,
  public.inspection_form_versions,
  public.inspection_form_sections,
  public.inspection_form_items,
  public.inspection_item_responses
to authenticated;

create or replace function private.can_view_inspection_template(p_template_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.is_user_active()
    and exists (
      select 1
      from public.inspection_form_templates t
      where t.id = p_template_id
        and (
          private.is_system_admin()
          or t.scope_type = 'system'
          or (t.scope_type = 'agency' and private.has_agency_access(t.agency_id))
        )
    );
$$;

create or replace function private.can_manage_inspection_template(p_template_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.is_user_active()
    and exists (
      select 1
      from public.inspection_form_templates t
      where t.id = p_template_id
        and (
          private.is_system_admin()
          or (
            t.scope_type = 'agency'
            and private.can_manage_agency_fleet(t.agency_id)
          )
        )
    );
$$;

revoke execute on function private.can_view_inspection_template(uuid) from public, anon;
revoke execute on function private.can_manage_inspection_template(uuid) from public, anon;
grant execute on function private.can_view_inspection_template(uuid) to authenticated;
grant execute on function private.can_manage_inspection_template(uuid) to authenticated;

drop policy if exists inspection_form_templates_read on public.inspection_form_templates;
create policy inspection_form_templates_read on public.inspection_form_templates
for select to authenticated
using (
  (select private.is_system_admin())
  or scope_type = 'system'
  or (scope_type = 'agency' and (select private.has_agency_access(agency_id)))
);

drop policy if exists inspection_form_templates_insert on public.inspection_form_templates;
create policy inspection_form_templates_insert on public.inspection_form_templates
for insert to authenticated
with check (
  (select private.is_system_admin())
  or (scope_type = 'agency' and (select private.can_manage_agency_fleet(agency_id)))
);

drop policy if exists inspection_form_templates_update on public.inspection_form_templates;
create policy inspection_form_templates_update on public.inspection_form_templates
for update to authenticated
using ((select private.can_manage_inspection_template(id)))
with check (
  (select private.is_system_admin())
  or (scope_type = 'agency' and (select private.can_manage_agency_fleet(agency_id)))
);

drop policy if exists inspection_form_templates_delete on public.inspection_form_templates;
create policy inspection_form_templates_delete on public.inspection_form_templates
for delete to authenticated using ((select private.is_system_admin()));

drop policy if exists inspection_form_versions_read on public.inspection_form_versions;
create policy inspection_form_versions_read on public.inspection_form_versions
for select to authenticated
using ((select private.can_view_inspection_template(template_id)));

drop policy if exists inspection_form_versions_write on public.inspection_form_versions;
create policy inspection_form_versions_write on public.inspection_form_versions
for all to authenticated
using ((select private.can_manage_inspection_template(template_id)))
with check ((select private.can_manage_inspection_template(template_id)));

drop policy if exists inspection_form_sections_read on public.inspection_form_sections;
create policy inspection_form_sections_read on public.inspection_form_sections
for select to authenticated
using (
  exists (
    select 1 from public.inspection_form_versions v
    where v.id = inspection_form_sections.form_version_id
      and (select private.can_view_inspection_template(v.template_id))
  )
);

drop policy if exists inspection_form_sections_write on public.inspection_form_sections;
create policy inspection_form_sections_write on public.inspection_form_sections
for all to authenticated
using (
  exists (
    select 1 from public.inspection_form_versions v
    where v.id = inspection_form_sections.form_version_id
      and (select private.can_manage_inspection_template(v.template_id))
  )
)
with check (
  exists (
    select 1 from public.inspection_form_versions v
    where v.id = inspection_form_sections.form_version_id
      and (select private.can_manage_inspection_template(v.template_id))
  )
);

drop policy if exists inspection_form_items_read on public.inspection_form_items;
create policy inspection_form_items_read on public.inspection_form_items
for select to authenticated
using (
  exists (
    select 1
    from public.inspection_form_sections s
    join public.inspection_form_versions v on v.id = s.form_version_id
    where s.id = inspection_form_items.section_id
      and (select private.can_view_inspection_template(v.template_id))
  )
);

drop policy if exists inspection_form_items_write on public.inspection_form_items;
create policy inspection_form_items_write on public.inspection_form_items
for all to authenticated
using (
  exists (
    select 1
    from public.inspection_form_sections s
    join public.inspection_form_versions v on v.id = s.form_version_id
    where s.id = inspection_form_items.section_id
      and (select private.can_manage_inspection_template(v.template_id))
  )
)
with check (
  exists (
    select 1
    from public.inspection_form_sections s
    join public.inspection_form_versions v on v.id = s.form_version_id
    where s.id = inspection_form_items.section_id
      and (select private.can_manage_inspection_template(v.template_id))
  )
);

drop policy if exists inspection_item_responses_read on public.inspection_item_responses;
create policy inspection_item_responses_read on public.inspection_item_responses
for select to authenticated
using (
  exists (
    select 1
    from public.vehicle_inspections vi
    where vi.id = inspection_item_responses.vehicle_inspection_id
      and (select private.can_view_vehicle(vi.vehicle_id))
  )
);

drop policy if exists inspection_item_responses_insert on public.inspection_item_responses;
create policy inspection_item_responses_insert on public.inspection_item_responses
for insert to authenticated
with check (
  exists (
    select 1
    from public.vehicle_inspections vi
    where vi.id = inspection_item_responses.vehicle_inspection_id
      and vi.workflow_status = 'draft'
      and (select private.can_manage_vehicle(vi.vehicle_id))
  )
);

drop policy if exists inspection_item_responses_update on public.inspection_item_responses;
create policy inspection_item_responses_update on public.inspection_item_responses
for update to authenticated
using (
  exists (
    select 1
    from public.vehicle_inspections vi
    where vi.id = inspection_item_responses.vehicle_inspection_id
      and vi.workflow_status = 'draft'
      and (select private.can_manage_vehicle(vi.vehicle_id))
  )
)
with check (
  exists (
    select 1
    from public.vehicle_inspections vi
    where vi.id = inspection_item_responses.vehicle_inspection_id
      and vi.workflow_status = 'draft'
      and (select private.can_manage_vehicle(vi.vehicle_id))
  )
);

drop policy if exists inspection_item_responses_delete on public.inspection_item_responses;
create policy inspection_item_responses_delete on public.inspection_item_responses
for delete to authenticated
using (
  exists (
    select 1
    from public.vehicle_inspections vi
    where vi.id = inspection_item_responses.vehicle_inspection_id
      and vi.workflow_status = 'draft'
      and (select private.can_manage_vehicle(vi.vehicle_id))
  )
);

drop policy if exists vehicle_inspections_update on public.vehicle_inspections;
create policy vehicle_inspections_update on public.vehicle_inspections
for update to authenticated
using (
  (select private.is_system_admin())
  or (
    workflow_status = 'draft'
    and (select private.can_manage_vehicle(vehicle_id))
  )
)
with check (
  (select private.is_system_admin())
  or (
    workflow_status in ('draft','submitted')
    and (select private.can_manage_vehicle(vehicle_id))
  )
);

do $$
declare t text;
begin
  foreach t in array array[
    'inspection_form_templates','inspection_form_versions','inspection_form_sections',
    'inspection_form_items','inspection_item_responses'
  ]
  loop
    execute format('drop trigger if exists %I on public.%I', 'set_' || t || '_updated_at', t);
    execute format(
      'create trigger %I before update on public.%I for each row execute function private.set_updated_at()',
      'set_' || t || '_updated_at', t
    );
  end loop;
end $$;

do $$
declare t text;
begin
  foreach t in array array[
    'inspection_form_templates','inspection_form_versions','inspection_form_sections',
    'inspection_form_items','inspection_item_responses'
  ]
  loop
    execute format('drop trigger if exists %I on public.%I', 'audit_' || t, t);
    execute format(
      'create trigger %I after insert or update or delete on public.%I for each row execute function private.audit_row_change()',
      'audit_' || t, t
    );
  end loop;
end $$;

insert into public.vehicle_types(code, name, sort_order)
values
  ('GEA_BLS_NON_TRANSPORT', 'GEA BLS Non-Transport', 5),
  ('GEA_BLS_AMBULANCE', 'GEA BLS Ambulance', 6),
  ('GEA_ALS_NON_TRANSPORT', 'GEA ALS Non-Transport', 7),
  ('GEA_ALS_AMBULANCE', 'GEA ALS Ambulance', 8),
  ('GEA_CC_TRANSPORT', 'GEA Critical Care Transport', 9)
on conflict (code) do update
set name = excluded.name, active = true, sort_order = excluded.sort_order;

insert into public.inspection_types(
  code, name, description, default_interval_months, requires_document,
  tracks_deficiencies, warning_days, active
)
values (
  'GEAEMS_VEHICLE_INSPECTION',
  'GEAEMS Vehicle Equipment Inspection',
  'Digital inspection based on the GEA/IDPH EMS vehicle requirements comparison matrix.',
  null, false, true, array[90,60,30,14,7,1], true
)
on conflict (code) do update
set name = excluded.name, description = excluded.description, active = true;


insert into public.inspection_form_templates(
  code, name, description, inspection_type_id, vehicle_type_id, scope_type, agency_id, active
)
select 'GEA_BLS_NON_TRANSPORT_EQUIPMENT', 'GEA BLS Non-Transport Equipment Inspection',
  'System inspection template seeded from gea-idph-ems-comparison-matrix.xlsx.',
  it.id, vt.id, 'system', null, true
from public.inspection_types it
join public.vehicle_types vt on vt.code = 'GEA_BLS_NON_TRANSPORT'
where it.code = 'GEAEMS_VEHICLE_INSPECTION'
on conflict (code) do update
set name = excluded.name, description = excluded.description,
    inspection_type_id = excluded.inspection_type_id,
    vehicle_type_id = excluded.vehicle_type_id, active = true;

insert into public.inspection_form_versions(template_id, version_number, status, source_name, published_at)
select t.id, 1, 'published', 'gea-idph-ems-comparison-matrix.xlsx', now()
from public.inspection_form_templates t
where t.code = 'GEA_BLS_NON_TRANSPORT_EQUIPMENT'
on conflict (template_id, version_number) do update
set status='published', source_name=excluded.source_name,
    published_at=coalesce(public.inspection_form_versions.published_at, excluded.published_at);

insert into public.inspection_form_sections(form_version_id, title, sort_order)
select v.id, '1. VEHICLE HARDWARE, CHASSIS & REGULATORY COMPLIANCE', 10
from public.inspection_form_versions v
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1
on conflict (form_version_id, sort_order) do update set title=excluded.title;

insert into public.inspection_form_sections(form_version_id, title, sort_order)
select v.id, '2. OXYGEN & SUCTION EQUIPMENT', 20
from public.inspection_form_versions v
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1
on conflict (form_version_id, sort_order) do update set title=excluded.title;

insert into public.inspection_form_sections(form_version_id, title, sort_order)
select v.id, '3. AIRWAY MANAGEMENT, VENTILATION & RESUSCITATION', 30
from public.inspection_form_versions v
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1
on conflict (form_version_id, sort_order) do update set title=excluded.title;

insert into public.inspection_form_sections(form_version_id, title, sort_order)
select v.id, '4. PATIENT ASSESSMENT & DIAGNOSTICS', 40
from public.inspection_form_versions v
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1
on conflict (form_version_id, sort_order) do update set title=excluded.title;

insert into public.inspection_form_sections(form_version_id, title, sort_order)
select v.id, '5. IMMOBILIZATION & SPINAL CARE', 50
from public.inspection_form_versions v
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1
on conflict (form_version_id, sort_order) do update set title=excluded.title;

insert into public.inspection_form_sections(form_version_id, title, sort_order)
select v.id, '6. BANDAGES, DRESSINGS & SURGICAL SUPPLIES', 60
from public.inspection_form_versions v
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1
on conflict (form_version_id, sort_order) do update set title=excluded.title;

insert into public.inspection_form_sections(form_version_id, title, sort_order)
select v.id, '7. MASS TRAUMA KITS & EXTRICATION GEAR', 70
from public.inspection_form_versions v
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1
on conflict (form_version_id, sort_order) do update set title=excluded.title;

insert into public.inspection_form_sections(form_version_id, title, sort_order)
select v.id, '8. CARDIAC MONITORING & RESUSCITATION HARDWARE', 80
from public.inspection_form_versions v
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1
on conflict (form_version_id, sort_order) do update set title=excluded.title;

insert into public.inspection_form_sections(form_version_id, title, sort_order)
select v.id, '9. INTRAVENOUS ACCESS, VASCULAR SUPPLIES & PUMPS', 90
from public.inspection_form_versions v
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1
on conflict (form_version_id, sort_order) do update set title=excluded.title;

insert into public.inspection_form_sections(form_version_id, title, sort_order)
select v.id, '10. EMERGENCY MEDICATIONS & FORMULARY (TOTAL REQUIRED UNITS)', 100
from public.inspection_form_versions v
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1
on conflict (form_version_id, sort_order) do update set title=excluded.title;

insert into public.inspection_form_sections(form_version_id, title, sort_order)
select v.id, '11. PEDIATRIC, FORMS & MISCELLANEOUS SUPPLIES', 110
from public.inspection_form_versions v
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1
on conflict (form_version_id, sort_order) do update set title=excluded.title;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R007', 'FCC Radio License (On File)', 'Required',
  'compliance', true, false, 'deficiency', false, 7, 50
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=10
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R008', 'MERCI / VHF Communications Radio', '1 (VHF)',
  'compliance', true, false, 'deficiency', false, 8, 60
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=10
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R014', 'Portable Oxygen Cylinder (w/ Regulator & Key)', '1',
  'compliance', true, false, 'deficiency', false, 14, 20
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=20
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R016', 'Oxygen Delivery Tubing', '1',
  'compliance', true, false, 'deficiency', false, 16, 40
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=20
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R017', 'Non-Rebreather Oxygen Masks (Adult)', '1',
  'compliance', true, false, 'deficiency', false, 17, 50
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=20
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R018', 'Non-Rebreather Oxygen Masks (Child/Pediatric)', '1',
  'compliance', true, false, 'deficiency', false, 18, 60
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=20
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R019', 'Non-Rebreather Oxygen Masks (Infant)', '1',
  'compliance', true, false, 'deficiency', false, 19, 70
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=20
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R020', 'Nasal Cannula (Adult)', '1',
  'compliance', true, false, 'deficiency', false, 20, 80
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=20
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R021', 'Nasal Cannula (Pediatric)', '1',
  'compliance', true, false, 'deficiency', false, 21, 90
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=20
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R023', 'Portable Suction Unit', '1',
  'compliance', true, false, 'deficiency', false, 23, 110
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=20
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R024', 'Suction Tubing', '1',
  'compliance', true, false, 'deficiency', false, 24, 120
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=20
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R025', 'Sterile Suction Catheters (6F - 18F)', '1 each size',
  'compliance', true, false, 'deficiency', false, 25, 130
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=20
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R026', 'Semi-Rigid Pharyngeal / Tonsil Tip Suction Catheters', '1',
  'compliance', true, false, 'deficiency', false, 26, 140
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=20
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R027', 'DuCanto Rigid Suction Catheter (9.3" x 0.26")', '1',
  'compliance', true, false, 'deficiency', false, 27, 150
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=20
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R030', 'Oropharyngeal Airways (OPAs, Sizes 40mm - 100mm)', '1 each (7 sizes)',
  'compliance', true, false, 'deficiency', false, 30, 10
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=30
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R031', 'Nasopharyngeal Airways (NPAs, Sizes 12F - 34F w/ Lube)', '1 each (12 sizes)',
  'compliance', true, false, 'deficiency', false, 31, 20
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=30
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R032', 'Adult Bag-Valve-Mask (BVM) w/ Transparent Mask', '1',
  'compliance', true, false, 'deficiency', false, 32, 30
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=30
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R033', 'Pediatric Bag-Valve-Mask (BVM) w/ Child Mask', '1',
  'compliance', true, false, 'deficiency', false, 33, 40
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=30
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R034', 'Neonatal / Infant Bag-Valve-Mask (BVM) w/ Mask', '1',
  'compliance', true, false, 'deficiency', false, 34, 50
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=30
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R035', 'Aerosol Masks (Adult & Pediatric)', '1 each',
  'compliance', true, false, 'deficiency', false, 35, 60
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=30
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R036', 'Hand-Held Nebulizers w/ Adapters', '1',
  'compliance', true, false, 'deficiency', false, 36, 70
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=30
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R037', 'CPAP Flow Safe II w/ Nebulizer (Large)', '1',
  'compliance', true, false, 'deficiency', false, 37, 80
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=30
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R038', 'i-Gel / i-Gel O2 Supraglottic Airways (Sizes 1.5 - 5)', '1 each size',
  'compliance', true, false, 'deficiency', false, 38, 90
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=30
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R052', 'Blood Pressure Cuffs w/ Gauge (Infant, Child, Adult, Lg Adult)', '1 set (4 sizes)',
  'compliance', true, false, 'deficiency', false, 52, 10
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=40
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R053', 'Stethoscopes', '1',
  'compliance', true, false, 'deficiency', false, 53, 20
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=40
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R054', 'Assessment Flashlights / Penlights', '1',
  'compliance', true, false, 'deficiency', false, 54, 30
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=40
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R055', 'Clinical Thermometer', '1',
  'compliance', true, false, 'deficiency', false, 55, 40
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=40
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R056', 'Blood Glucose Measuring Kit (Meter, Strips, Lancets, Reagent)', '1 kit',
  'compliance', true, false, 'deficiency', false, 56, 50
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=40
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R057', 'Blood Glucose Test Strip Bottles (Extra)', '1 bottle',
  'compliance', true, false, 'deficiency', false, 57, 60
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=40
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R058', 'Pulse Oximeter w/ Adult & Pediatric Sensors', '1 set sensors',
  'compliance', true, false, 'deficiency', false, 58, 70
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=40
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R060', 'Cervical Collars, Adjustable / Rigid', '1 each (3 sizes)',
  'compliance', true, false, 'deficiency', false, 60, 10
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=50
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R061', 'Long Spine Backboard w/ 3 Sets Torso Straps', '1 optional',
  'compliance', true, false, 'deficiency', false, 61, 20
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=50
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R063', 'Lower Extremity Traction Splint (Adult & Pediatric)', '1 adult',
  'compliance', true, false, 'deficiency', false, 63, 40
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=50
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R064', 'Extremity Splints (Adult Long/Short, Peds Long/Short)', '1 each (4 sizes)',
  'compliance', true, false, 'deficiency', false, 64, 50
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=50
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R065', 'Triangular Bandages / Slings', '2',
  'compliance', true, false, 'deficiency', false, 65, 60
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=50
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R066', 'Lateral Head Immobilization Device', '1 optional',
  'compliance', true, false, 'deficiency', false, 66, 70
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=50
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R070', 'Commercial Arterial Tourniquets (Hemorrhage Control)', '2',
  'compliance', true, false, 'deficiency', false, 70, 10
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=60
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R071', 'Sterile Gauze Pads (4" x 4", Single Packages)', '10',
  'compliance', true, false, 'deficiency', false, 71, 20
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=60
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R072', 'Trauma Dressings / Universal Dressings (12" x 30")', '2',
  'compliance', true, false, 'deficiency', false, 72, 30
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=60
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R073', 'Soft Roller Bandages (4" Kerlix Rolls)', '4',
  'compliance', true, false, 'deficiency', false, 73, 40
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=60
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R074', 'Occlusive Vaseline Gauze (3" x 8") / Vented Chest Seal', '1',
  'compliance', true, false, 'deficiency', false, 74, 50
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=60
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R075', 'Adhesive Tape Rolls (Paper or Plastic)', '2',
  'compliance', true, false, 'deficiency', false, 75, 60
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=60
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R076', 'Saran Wrap (Burn Treatment)', '1',
  'compliance', true, false, 'deficiency', false, 76, 70
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=60
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R077', 'Adhesive Band-Aids', '10',
  'compliance', true, false, 'deficiency', false, 77, 80
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=60
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R078', 'Burn Sheets (Clean, Individually Wrapped)', '1',
  'compliance', true, false, 'deficiency', false, 78, 90
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=60
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R079', 'Heavy-Duty Bandage Shears / Scissors', '1',
  'compliance', true, false, 'deficiency', false, 79, 100
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=60
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R080', 'Pour Bottles 0.9% Normal Saline (1000 mL)', '1',
  'compliance', true, false, 'deficiency', false, 80, 110
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=60
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R081', 'Pour Bottles Sterile Water (1000 mL)', '1',
  'compliance', true, false, 'deficiency', false, 81, 120
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=60
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R083', 'Mass Trauma Bag (BLS / ALS System Standard)', '1 BLS Bag',
  'compliance', true, false, 'deficiency', false, 83, 10
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=70
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R084', 'Wrecking Bar (24" or Larger)', '1',
  'compliance', true, false, 'deficiency', false, 84, 20
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=70
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R085', 'Safety Goggles', '2',
  'compliance', true, false, 'deficiency', false, 85, 30
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=70
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R086', '5# ABC Fire Extinguishers w/ Tag', '2',
  'compliance', true, false, 'deficiency', false, 86, 40
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=70
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R087', 'Roadside Warning Devices (Reflective / Illuminated)', '1 set',
  'compliance', true, false, 'deficiency', false, 87, 50
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=70
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R090', 'Automated External Defibrillator (AED) w/ Adult & Peds Pads', '1 AED',
  'compliance', true, false, 'deficiency', false, 90, 10
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=80
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R092', 'Adult Defibrillator / Pacing Pads', '1 set',
  'compliance', true, false, 'deficiency', false, 92, 30
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=80
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R093', 'Pediatric Defibrillator / Pacing Pads', '1 set',
  'compliance', true, false, 'deficiency', false, 93, 40
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=80
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R105', 'Alcohol Prep Pads', '5',
  'compliance', true, false, 'deficiency', false, 105, 70
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=90
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R112', 'Albuterol 2.5mg/3mL (Inhalation Solution)', '10 mg (4 doses)',
  'compliance', true, false, 'deficiency', false, 112, 10
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R113', 'Aspirin 81mg Chewable Tablets', '648 mg (8 tabs)',
  'compliance', true, false, 'deficiency', false, 113, 20
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R114', 'Diphenhydramine (Benadryl) 50mg Vial', '50 mg',
  'compliance', true, false, 'deficiency', false, 114, 30
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R115', 'Epinephrine 1mg/mL (1:1,000 Ampules/Vials)', '2 mg (2 amp)',
  'compliance', true, false, 'deficiency', false, 115, 40
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R117', 'Glucagon 1mg Injectable Kit', '1 mg',
  'compliance', true, false, 'deficiency', false, 117, 60
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R118', 'Oral Glucose Gel (15g Tubes)', '30 g (2 tubes)',
  'compliance', true, false, 'deficiency', false, 118, 70
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R119', 'Ipratropium Bromide (Atrovent) 0.02%', '1.0 mg (2 doses)',
  'compliance', true, false, 'deficiency', false, 119, 80
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R120', 'Naloxone (Narcan) 2mg/2mL Preloads', '4 mg (2 pre)',
  'compliance', true, false, 'deficiency', false, 120, 90
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R121', 'Nitroglycerin SL Tablets (Bottle)', '1 bottle',
  'compliance', true, false, 'deficiency', false, 121, 100
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R122', 'Ondansetron (Zofran) 4mg Oral Dissolve Tabs', '8 mg (2 tabs)',
  'compliance', true, false, 'deficiency', false, 122, 110
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R145', 'Broselow Length-Based Assessment Tape', '1',
  'compliance', true, false, 'deficiency', false, 145, 10
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=110
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R146', 'Pediatric Trauma Score Reference', '1',
  'compliance', true, false, 'deficiency', false, 146, 20
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=110
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R147', 'Silver Swaddler & Newborn Head Cover', '1 each',
  'compliance', true, false, 'deficiency', false, 147, 30
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=110
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R148', 'Sterile Obstetrical Kit w/ Bulb Syringe', '1 kit',
  'compliance', true, false, 'deficiency', false, 148, 40
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=110
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R149', 'Disaster Triage Tags (SMART Tags - 20 w/ START/JumpSTART)', '1 kit (20)',
  'compliance', true, false, 'deficiency', false, 149, 50
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=110
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R150', 'Ambulance Patient Care Run Report Backups (Paper)', '5',
  'compliance', true, false, 'deficiency', false, 150, 60
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=110
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R151', 'GEA Standing Medical Orders (SMO Printed Copy)', '1',
  'compliance', true, false, 'deficiency', false, 151, 70
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=110
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R152', 'Blankets (Mylar or Cloth)', '1',
  'compliance', true, false, 'deficiency', false, 152, 80
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=110
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R153', 'Sheets & Towels', '2 towels',
  'compliance', true, false, 'deficiency', false, 153, 90
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=110
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R155', 'Cold Packs / Thermal Packs', '2 cold / 2 warm',
  'compliance', true, false, 'deficiency', false, 155, 110
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=110
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R156', 'PPE (Gloves, Gowns, Masks, Eye Protection, Biohazard Bags)', 'Required',
  'compliance', true, false, 'deficiency', false, 156, 120
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=110
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R157', 'ANSI Reflective Vests', '1 / provider',
  'compliance', true, false, 'deficiency', false, 157, 130
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=110
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R158', 'Sharps Container & Ampule Breaker', '1 sharps, 2 amp',
  'compliance', true, false, 'deficiency', false, 158, 140
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=110
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R159', 'Chemical Disinfectants (Hand Cleanser & Surface Cleaner)', '1 each',
  'compliance', true, false, 'deficiency', false, 159, 150
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=110
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_templates(
  code, name, description, inspection_type_id, vehicle_type_id, scope_type, agency_id, active
)
select 'GEA_BLS_AMBULANCE_EQUIPMENT', 'GEA BLS Ambulance Equipment Inspection',
  'System inspection template seeded from gea-idph-ems-comparison-matrix.xlsx.',
  it.id, vt.id, 'system', null, true
from public.inspection_types it
join public.vehicle_types vt on vt.code = 'GEA_BLS_AMBULANCE'
where it.code = 'GEAEMS_VEHICLE_INSPECTION'
on conflict (code) do update
set name = excluded.name, description = excluded.description,
    inspection_type_id = excluded.inspection_type_id,
    vehicle_type_id = excluded.vehicle_type_id, active = true;

insert into public.inspection_form_versions(template_id, version_number, status, source_name, published_at)
select t.id, 1, 'published', 'gea-idph-ems-comparison-matrix.xlsx', now()
from public.inspection_form_templates t
where t.code = 'GEA_BLS_AMBULANCE_EQUIPMENT'
on conflict (template_id, version_number) do update
set status='published', source_name=excluded.source_name,
    published_at=coalesce(public.inspection_form_versions.published_at, excluded.published_at);

insert into public.inspection_form_sections(form_version_id, title, sort_order)
select v.id, '1. VEHICLE HARDWARE, CHASSIS & REGULATORY COMPLIANCE', 10
from public.inspection_form_versions v
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1
on conflict (form_version_id, sort_order) do update set title=excluded.title;

insert into public.inspection_form_sections(form_version_id, title, sort_order)
select v.id, '2. OXYGEN & SUCTION EQUIPMENT', 20
from public.inspection_form_versions v
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1
on conflict (form_version_id, sort_order) do update set title=excluded.title;

insert into public.inspection_form_sections(form_version_id, title, sort_order)
select v.id, '3. AIRWAY MANAGEMENT, VENTILATION & RESUSCITATION', 30
from public.inspection_form_versions v
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1
on conflict (form_version_id, sort_order) do update set title=excluded.title;

insert into public.inspection_form_sections(form_version_id, title, sort_order)
select v.id, '4. PATIENT ASSESSMENT & DIAGNOSTICS', 40
from public.inspection_form_versions v
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1
on conflict (form_version_id, sort_order) do update set title=excluded.title;

insert into public.inspection_form_sections(form_version_id, title, sort_order)
select v.id, '5. IMMOBILIZATION & SPINAL CARE', 50
from public.inspection_form_versions v
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1
on conflict (form_version_id, sort_order) do update set title=excluded.title;

insert into public.inspection_form_sections(form_version_id, title, sort_order)
select v.id, '6. BANDAGES, DRESSINGS & SURGICAL SUPPLIES', 60
from public.inspection_form_versions v
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1
on conflict (form_version_id, sort_order) do update set title=excluded.title;

insert into public.inspection_form_sections(form_version_id, title, sort_order)
select v.id, '7. MASS TRAUMA KITS & EXTRICATION GEAR', 70
from public.inspection_form_versions v
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1
on conflict (form_version_id, sort_order) do update set title=excluded.title;

insert into public.inspection_form_sections(form_version_id, title, sort_order)
select v.id, '8. CARDIAC MONITORING & RESUSCITATION HARDWARE', 80
from public.inspection_form_versions v
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1
on conflict (form_version_id, sort_order) do update set title=excluded.title;

insert into public.inspection_form_sections(form_version_id, title, sort_order)
select v.id, '9. INTRAVENOUS ACCESS, VASCULAR SUPPLIES & PUMPS', 90
from public.inspection_form_versions v
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1
on conflict (form_version_id, sort_order) do update set title=excluded.title;

insert into public.inspection_form_sections(form_version_id, title, sort_order)
select v.id, '10. EMERGENCY MEDICATIONS & FORMULARY (TOTAL REQUIRED UNITS)', 100
from public.inspection_form_versions v
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1
on conflict (form_version_id, sort_order) do update set title=excluded.title;

insert into public.inspection_form_sections(form_version_id, title, sort_order)
select v.id, '11. PEDIATRIC, FORMS & MISCELLANEOUS SUPPLIES', 110
from public.inspection_form_versions v
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1
on conflict (form_version_id, sort_order) do update set title=excluded.title;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R003', 'Primary Patient Cot', '1',
  'compliance', true, false, 'deficiency', false, 3, 10
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=10
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R004', 'Secondary Patient Stretcher', '1',
  'compliance', true, false, 'deficiency', false, 4, 20
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=10
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R005', 'IDOT Safety Inspection Sticker (Current & Valid)', '1',
  'compliance', true, false, 'deficiency', false, 5, 30
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=10
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R006', 'IDPH Central Complaint Registry Sticker', '1',
  'compliance', true, false, 'deficiency', false, 6, 40
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=10
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R007', 'FCC Radio License (On File)', 'Required',
  'compliance', true, false, 'deficiency', false, 7, 50
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=10
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R008', 'MERCI / VHF Communications Radio', '1 (VHF)',
  'compliance', true, false, 'deficiency', false, 8, 60
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=10
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R011', 'Electric Clock w/ Sweep Second Hand', '1',
  'compliance', true, false, 'deficiency', false, 11, 90
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=10
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R013', 'On-Board Oxygen Cylinder (Main System)', '1',
  'compliance', true, false, 'deficiency', false, 13, 10
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=20
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R014', 'Portable Oxygen Cylinder (w/ Regulator & Key)', '1',
  'compliance', true, false, 'deficiency', false, 14, 20
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=20
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R015', 'Spare Oxygen D or E Cylinder', '1',
  'compliance', true, false, 'deficiency', false, 15, 30
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=20
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R016', 'Oxygen Delivery Tubing', '2',
  'compliance', true, false, 'deficiency', false, 16, 40
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=20
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R017', 'Non-Rebreather Oxygen Masks (Adult)', '2',
  'compliance', true, false, 'deficiency', false, 17, 50
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=20
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R018', 'Non-Rebreather Oxygen Masks (Child/Pediatric)', '2',
  'compliance', true, false, 'deficiency', false, 18, 60
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=20
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R019', 'Non-Rebreather Oxygen Masks (Infant)', '2',
  'compliance', true, false, 'deficiency', false, 19, 70
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=20
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R020', 'Nasal Cannula (Adult)', '3',
  'compliance', true, false, 'deficiency', false, 20, 80
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=20
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R021', 'Nasal Cannula (Pediatric)', '3',
  'compliance', true, false, 'deficiency', false, 21, 90
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=20
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R022', 'On-Board Suction System', '1',
  'compliance', true, false, 'deficiency', false, 22, 100
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=20
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R023', 'Portable Suction Unit', '1',
  'compliance', true, false, 'deficiency', false, 23, 110
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=20
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R024', 'Suction Tubing', '3',
  'compliance', true, false, 'deficiency', false, 24, 120
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=20
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R025', 'Sterile Suction Catheters (6F - 18F)', '2 each size',
  'compliance', true, false, 'deficiency', false, 25, 130
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=20
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R026', 'Semi-Rigid Pharyngeal / Tonsil Tip Suction Catheters', '3',
  'compliance', true, false, 'deficiency', false, 26, 140
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=20
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R027', 'DuCanto Rigid Suction Catheter (9.3" x 0.26")', '1',
  'compliance', true, false, 'deficiency', false, 27, 150
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=20
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R028', 'Sterile Suction Kit', '1',
  'compliance', true, false, 'deficiency', false, 28, 160
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=20
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R030', 'Oropharyngeal Airways (OPAs, Sizes 40mm - 100mm)', '1 each (7 sizes)',
  'compliance', true, false, 'deficiency', false, 30, 10
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=30
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R031', 'Nasopharyngeal Airways (NPAs, Sizes 12F - 34F w/ Lube)', '1 each (12 sizes)',
  'compliance', true, false, 'deficiency', false, 31, 20
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=30
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R032', 'Adult Bag-Valve-Mask (BVM) w/ Transparent Mask', '1',
  'compliance', true, false, 'deficiency', false, 32, 30
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=30
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R033', 'Pediatric Bag-Valve-Mask (BVM) w/ Child Mask', '1',
  'compliance', true, false, 'deficiency', false, 33, 40
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=30
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R034', 'Neonatal / Infant Bag-Valve-Mask (BVM) w/ Mask', '1',
  'compliance', true, false, 'deficiency', false, 34, 50
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=30
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R035', 'Aerosol Masks (Adult & Pediatric)', '2 each',
  'compliance', true, false, 'deficiency', false, 35, 60
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=30
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R036', 'Hand-Held Nebulizers w/ Adapters', '2',
  'compliance', true, false, 'deficiency', false, 36, 70
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=30
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R037', 'CPAP Flow Safe II w/ Nebulizer (Large)', '1',
  'compliance', true, false, 'deficiency', false, 37, 80
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=30
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R038', 'i-Gel / i-Gel O2 Supraglottic Airways (Sizes 1.5 - 5)', '1 each size',
  'compliance', true, false, 'deficiency', false, 38, 90
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=30
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R052', 'Blood Pressure Cuffs w/ Gauge (Infant, Child, Adult, Lg Adult)', '1 set (4 sizes)',
  'compliance', true, false, 'deficiency', false, 52, 10
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=40
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R053', 'Stethoscopes', '2',
  'compliance', true, false, 'deficiency', false, 53, 20
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=40
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R054', 'Assessment Flashlights / Penlights', '2',
  'compliance', true, false, 'deficiency', false, 54, 30
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=40
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R055', 'Clinical Thermometer', '1',
  'compliance', true, false, 'deficiency', false, 55, 40
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=40
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R056', 'Blood Glucose Measuring Kit (Meter, Strips, Lancets, Reagent)', '1 kit',
  'compliance', true, false, 'deficiency', false, 56, 50
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=40
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R057', 'Blood Glucose Test Strip Bottles (Extra)', '2 bottles',
  'compliance', true, false, 'deficiency', false, 57, 60
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=40
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R058', 'Pulse Oximeter w/ Adult & Pediatric Sensors', '1 set sensors',
  'compliance', true, false, 'deficiency', false, 58, 70
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=40
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R060', 'Cervical Collars, Adjustable / Rigid', '5 total',
  'compliance', true, false, 'deficiency', false, 60, 10
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=50
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R061', 'Long Spine Backboard w/ 3 Sets Torso Straps', '2 boards + 6 straps',
  'compliance', true, false, 'deficiency', false, 61, 20
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=50
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R062', 'Short Spine Board or KED Extrication Device', '1 device',
  'compliance', true, false, 'deficiency', false, 62, 30
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=50
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R063', 'Lower Extremity Traction Splint (Adult & Pediatric)', '1 adult & peds',
  'compliance', true, false, 'deficiency', false, 63, 40
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=50
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R064', 'Extremity Splints (Adult Long/Short, Peds Long/Short)', '2 each (8 sizes)',
  'compliance', true, false, 'deficiency', false, 64, 50
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=50
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R065', 'Triangular Bandages / Slings', '5',
  'compliance', true, false, 'deficiency', false, 65, 60
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=50
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R066', 'Lateral Head Immobilization Device', '2 set',
  'compliance', true, false, 'deficiency', false, 66, 70
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=50
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R068', 'Medical Grade Limb Restraints (Sets)', '1 set per limb',
  'compliance', true, false, 'deficiency', false, 68, 90
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=50
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R070', 'Commercial Arterial Tourniquets (Hemorrhage Control)', '2',
  'compliance', true, false, 'deficiency', false, 70, 10
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=60
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R071', 'Sterile Gauze Pads (4" x 4", Single Packages)', '20',
  'compliance', true, false, 'deficiency', false, 71, 20
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=60
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R072', 'Trauma Dressings / Universal Dressings (12" x 30")', '6',
  'compliance', true, false, 'deficiency', false, 72, 30
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=60
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R073', 'Soft Roller Bandages (4" Kerlix Rolls)', '10',
  'compliance', true, false, 'deficiency', false, 73, 40
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=60
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R074', 'Occlusive Vaseline Gauze (3" x 8") / Vented Chest Seal', '2',
  'compliance', true, false, 'deficiency', false, 74, 50
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=60
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R075', 'Adhesive Tape Rolls (Paper or Plastic)', '2',
  'compliance', true, false, 'deficiency', false, 75, 60
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=60
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R076', 'Saran Wrap (Burn Treatment)', '1',
  'compliance', true, false, 'deficiency', false, 76, 70
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=60
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R077', 'Adhesive Band-Aids', '10',
  'compliance', true, false, 'deficiency', false, 77, 80
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=60
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R078', 'Burn Sheets (Clean, Individually Wrapped)', '2',
  'compliance', true, false, 'deficiency', false, 78, 90
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=60
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R079', 'Heavy-Duty Bandage Shears / Scissors', '1',
  'compliance', true, false, 'deficiency', false, 79, 100
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=60
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R080', 'Pour Bottles 0.9% Normal Saline (1000 mL)', '2',
  'compliance', true, false, 'deficiency', false, 80, 110
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=60
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R081', 'Pour Bottles Sterile Water (1000 mL)', '1',
  'compliance', true, false, 'deficiency', false, 81, 120
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=60
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R083', 'Mass Trauma Bag (BLS / ALS System Standard)', '1 BLS Bag',
  'compliance', true, false, 'deficiency', false, 83, 10
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=70
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R084', 'Wrecking Bar (24" or Larger)', '1',
  'compliance', true, false, 'deficiency', false, 84, 20
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=70
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R085', 'Safety Goggles', '2',
  'compliance', true, false, 'deficiency', false, 85, 30
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=70
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R086', '5# ABC Fire Extinguishers w/ Tag', '2',
  'compliance', true, false, 'deficiency', false, 86, 40
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=70
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R087', 'Roadside Warning Devices (Reflective / Illuminated)', '1 set',
  'compliance', true, false, 'deficiency', false, 87, 50
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=70
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R088', 'Stair Chair / Collapsible Evacuation Chair', '1',
  'compliance', true, false, 'deficiency', false, 88, 60
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=70
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R090', 'Automated External Defibrillator (AED) w/ Adult & Peds Pads', '1 AED',
  'compliance', true, false, 'deficiency', false, 90, 10
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=80
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R092', 'Adult Defibrillator / Pacing Pads', '1 set',
  'compliance', true, false, 'deficiency', false, 92, 30
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=80
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R093', 'Pediatric Defibrillator / Pacing Pads', '1 set',
  'compliance', true, false, 'deficiency', false, 93, 40
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=80
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R105', 'Alcohol Prep Pads', '5',
  'compliance', true, false, 'deficiency', false, 105, 70
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=90
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R112', 'Albuterol 2.5mg/3mL (Inhalation Solution)', '20 mg (8 doses)',
  'compliance', true, false, 'deficiency', false, 112, 10
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R113', 'Aspirin 81mg Chewable Tablets', '648 mg (8 tabs)',
  'compliance', true, false, 'deficiency', false, 113, 20
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R114', 'Diphenhydramine (Benadryl) 50mg Vial', '50 mg',
  'compliance', true, false, 'deficiency', false, 114, 30
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R115', 'Epinephrine 1mg/mL (1:1,000 Ampules/Vials)', '4 mg (4 amp)',
  'compliance', true, false, 'deficiency', false, 115, 40
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R117', 'Glucagon 1mg Injectable Kit', '1 mg',
  'compliance', true, false, 'deficiency', false, 117, 60
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R118', 'Oral Glucose Gel (15g Tubes)', '30 g (2 tubes)',
  'compliance', true, false, 'deficiency', false, 118, 70
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R119', 'Ipratropium Bromide (Atrovent) 0.02%', '2.0 mg (4 doses)',
  'compliance', true, false, 'deficiency', false, 119, 80
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R120', 'Naloxone (Narcan) 2mg/2mL Preloads', '8 mg (4 pre)',
  'compliance', true, false, 'deficiency', false, 120, 90
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R121', 'Nitroglycerin SL Tablets (Bottle)', '1 bottle',
  'compliance', true, false, 'deficiency', false, 121, 100
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R122', 'Ondansetron (Zofran) 4mg Oral Dissolve Tabs', '8 mg (2 tabs)',
  'compliance', true, false, 'deficiency', false, 122, 110
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R145', 'Broselow Length-Based Assessment Tape', '1',
  'compliance', true, false, 'deficiency', false, 145, 10
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=110
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R146', 'Pediatric Trauma Score Reference', '1',
  'compliance', true, false, 'deficiency', false, 146, 20
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=110
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R147', 'Silver Swaddler & Newborn Head Cover', '1 each',
  'compliance', true, false, 'deficiency', false, 147, 30
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=110
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R148', 'Sterile Obstetrical Kit w/ Bulb Syringe', '1 kit',
  'compliance', true, false, 'deficiency', false, 148, 40
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=110
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R149', 'Disaster Triage Tags (SMART Tags - 20 w/ START/JumpSTART)', '1 kit (20)',
  'compliance', true, false, 'deficiency', false, 149, 50
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=110
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R150', 'Ambulance Patient Care Run Report Backups (Paper)', '10',
  'compliance', true, false, 'deficiency', false, 150, 60
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=110
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R151', 'GEA Standing Medical Orders (SMO Printed Copy)', '1',
  'compliance', true, false, 'deficiency', false, 151, 70
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=110
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R152', 'Blankets (Mylar or Cloth)', '2',
  'compliance', true, false, 'deficiency', false, 152, 80
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=110
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R153', 'Sheets & Towels', '2 sheets, 2 towels',
  'compliance', true, false, 'deficiency', false, 153, 90
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=110
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R154', 'Urinal & Bedpan', '1 each',
  'compliance', true, false, 'deficiency', false, 154, 100
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=110
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R155', 'Cold Packs / Thermal Packs', '8 cold / 3 warm',
  'compliance', true, false, 'deficiency', false, 155, 110
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=110
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R156', 'PPE (Gloves, Gowns, Masks, Eye Protection, Biohazard Bags)', 'Required',
  'compliance', true, false, 'deficiency', false, 156, 120
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=110
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R157', 'ANSI Reflective Vests', '1 / provider',
  'compliance', true, false, 'deficiency', false, 157, 130
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=110
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R158', 'Sharps Container & Ampule Breaker', '1 sharps, 2 amp',
  'compliance', true, false, 'deficiency', false, 158, 140
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=110
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R159', 'Chemical Disinfectants (Hand Cleanser & Surface Cleaner)', '1 each',
  'compliance', true, false, 'deficiency', false, 159, 150
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_BLS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=110
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_templates(
  code, name, description, inspection_type_id, vehicle_type_id, scope_type, agency_id, active
)
select 'GEA_ALS_NON_TRANSPORT_EQUIPMENT', 'GEA ALS Non-Transport Equipment Inspection',
  'System inspection template seeded from gea-idph-ems-comparison-matrix.xlsx.',
  it.id, vt.id, 'system', null, true
from public.inspection_types it
join public.vehicle_types vt on vt.code = 'GEA_ALS_NON_TRANSPORT'
where it.code = 'GEAEMS_VEHICLE_INSPECTION'
on conflict (code) do update
set name = excluded.name, description = excluded.description,
    inspection_type_id = excluded.inspection_type_id,
    vehicle_type_id = excluded.vehicle_type_id, active = true;

insert into public.inspection_form_versions(template_id, version_number, status, source_name, published_at)
select t.id, 1, 'published', 'gea-idph-ems-comparison-matrix.xlsx', now()
from public.inspection_form_templates t
where t.code = 'GEA_ALS_NON_TRANSPORT_EQUIPMENT'
on conflict (template_id, version_number) do update
set status='published', source_name=excluded.source_name,
    published_at=coalesce(public.inspection_form_versions.published_at, excluded.published_at);

insert into public.inspection_form_sections(form_version_id, title, sort_order)
select v.id, '1. VEHICLE HARDWARE, CHASSIS & REGULATORY COMPLIANCE', 10
from public.inspection_form_versions v
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1
on conflict (form_version_id, sort_order) do update set title=excluded.title;

insert into public.inspection_form_sections(form_version_id, title, sort_order)
select v.id, '2. OXYGEN & SUCTION EQUIPMENT', 20
from public.inspection_form_versions v
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1
on conflict (form_version_id, sort_order) do update set title=excluded.title;

insert into public.inspection_form_sections(form_version_id, title, sort_order)
select v.id, '3. AIRWAY MANAGEMENT, VENTILATION & RESUSCITATION', 30
from public.inspection_form_versions v
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1
on conflict (form_version_id, sort_order) do update set title=excluded.title;

insert into public.inspection_form_sections(form_version_id, title, sort_order)
select v.id, '4. PATIENT ASSESSMENT & DIAGNOSTICS', 40
from public.inspection_form_versions v
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1
on conflict (form_version_id, sort_order) do update set title=excluded.title;

insert into public.inspection_form_sections(form_version_id, title, sort_order)
select v.id, '5. IMMOBILIZATION & SPINAL CARE', 50
from public.inspection_form_versions v
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1
on conflict (form_version_id, sort_order) do update set title=excluded.title;

insert into public.inspection_form_sections(form_version_id, title, sort_order)
select v.id, '6. BANDAGES, DRESSINGS & SURGICAL SUPPLIES', 60
from public.inspection_form_versions v
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1
on conflict (form_version_id, sort_order) do update set title=excluded.title;

insert into public.inspection_form_sections(form_version_id, title, sort_order)
select v.id, '7. MASS TRAUMA KITS & EXTRICATION GEAR', 70
from public.inspection_form_versions v
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1
on conflict (form_version_id, sort_order) do update set title=excluded.title;

insert into public.inspection_form_sections(form_version_id, title, sort_order)
select v.id, '8. CARDIAC MONITORING & RESUSCITATION HARDWARE', 80
from public.inspection_form_versions v
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1
on conflict (form_version_id, sort_order) do update set title=excluded.title;

insert into public.inspection_form_sections(form_version_id, title, sort_order)
select v.id, '9. INTRAVENOUS ACCESS, VASCULAR SUPPLIES & PUMPS', 90
from public.inspection_form_versions v
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1
on conflict (form_version_id, sort_order) do update set title=excluded.title;

insert into public.inspection_form_sections(form_version_id, title, sort_order)
select v.id, '10. EMERGENCY MEDICATIONS & FORMULARY (TOTAL REQUIRED UNITS)', 100
from public.inspection_form_versions v
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1
on conflict (form_version_id, sort_order) do update set title=excluded.title;

insert into public.inspection_form_sections(form_version_id, title, sort_order)
select v.id, '11. PEDIATRIC, FORMS & MISCELLANEOUS SUPPLIES', 110
from public.inspection_form_versions v
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1
on conflict (form_version_id, sort_order) do update set title=excluded.title;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R007', 'FCC Radio License (On File)', 'Required',
  'compliance', true, false, 'deficiency', false, 7, 50
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=10
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R008', 'MERCI / VHF Communications Radio', '1 (VHF)',
  'compliance', true, false, 'deficiency', false, 8, 60
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=10
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R014', 'Portable Oxygen Cylinder (w/ Regulator & Key)', '1',
  'compliance', true, false, 'deficiency', false, 14, 20
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=20
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R016', 'Oxygen Delivery Tubing', '1',
  'compliance', true, false, 'deficiency', false, 16, 40
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=20
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R017', 'Non-Rebreather Oxygen Masks (Adult)', '2',
  'compliance', true, false, 'deficiency', false, 17, 50
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=20
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R018', 'Non-Rebreather Oxygen Masks (Child/Pediatric)', '2',
  'compliance', true, false, 'deficiency', false, 18, 60
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=20
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R019', 'Non-Rebreather Oxygen Masks (Infant)', '2',
  'compliance', true, false, 'deficiency', false, 19, 70
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=20
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R020', 'Nasal Cannula (Adult)', '3',
  'compliance', true, false, 'deficiency', false, 20, 80
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=20
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R021', 'Nasal Cannula (Pediatric)', '3',
  'compliance', true, false, 'deficiency', false, 21, 90
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=20
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R023', 'Portable Suction Unit', '1',
  'compliance', true, false, 'deficiency', false, 23, 110
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=20
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R024', 'Suction Tubing', '1',
  'compliance', true, false, 'deficiency', false, 24, 120
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=20
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R025', 'Sterile Suction Catheters (6F - 18F)', '1 each size',
  'compliance', true, false, 'deficiency', false, 25, 130
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=20
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R026', 'Semi-Rigid Pharyngeal / Tonsil Tip Suction Catheters', '1',
  'compliance', true, false, 'deficiency', false, 26, 140
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=20
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R027', 'DuCanto Rigid Suction Catheter (9.3" x 0.26")', '1',
  'compliance', true, false, 'deficiency', false, 27, 150
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=20
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R030', 'Oropharyngeal Airways (OPAs, Sizes 40mm - 100mm)', '1 each (7 sizes)',
  'compliance', true, false, 'deficiency', false, 30, 10
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=30
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R031', 'Nasopharyngeal Airways (NPAs, Sizes 12F - 34F w/ Lube)', '1 each (12 sizes)',
  'compliance', true, false, 'deficiency', false, 31, 20
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=30
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R032', 'Adult Bag-Valve-Mask (BVM) w/ Transparent Mask', '1',
  'compliance', true, false, 'deficiency', false, 32, 30
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=30
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R033', 'Pediatric Bag-Valve-Mask (BVM) w/ Child Mask', '1',
  'compliance', true, false, 'deficiency', false, 33, 40
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=30
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R034', 'Neonatal / Infant Bag-Valve-Mask (BVM) w/ Mask', '1',
  'compliance', true, false, 'deficiency', false, 34, 50
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=30
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R035', 'Aerosol Masks (Adult & Pediatric)', '1 each',
  'compliance', true, false, 'deficiency', false, 35, 60
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=30
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R036', 'Hand-Held Nebulizers w/ Adapters', '1',
  'compliance', true, false, 'deficiency', false, 36, 70
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=30
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R037', 'CPAP Flow Safe II w/ Nebulizer (Large)', '1',
  'compliance', true, false, 'deficiency', false, 37, 80
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=30
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R038', 'i-Gel / i-Gel O2 Supraglottic Airways (Sizes 1.5 - 5)', '1 each size',
  'compliance', true, false, 'deficiency', false, 38, 90
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=30
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R039', 'Endotracheal Tubes (ETTs, Sizes 3.0 - 8.5)', '1 set (12 sizes)',
  'compliance', true, false, 'deficiency', false, 39, 100
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=30
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R040', 'Laryngoscope Handles (Adult & Pediatric)', '1 each',
  'compliance', true, false, 'deficiency', false, 40, 110
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=30
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R041', 'Fiberoptic Laryngoscope Blades (Miller 1-4, Mac 2-4)', '1 set',
  'compliance', true, false, 'deficiency', false, 41, 120
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=30
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R042', 'Endotracheal Intubation Stylets (Adult & Pediatric)', '1 each',
  'compliance', true, false, 'deficiency', false, 42, 130
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=30
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R043', 'Intubating Bougie', '1',
  'compliance', true, false, 'deficiency', false, 43, 140
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=30
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R044', 'Magill Forceps (Adult & Pediatric)', '1 each',
  'compliance', true, false, 'deficiency', false, 44, 150
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=30
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R045', 'Surgical Cricothyrotomy Kit', '1 kit',
  'compliance', true, false, 'deficiency', false, 45, 160
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=30
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R046', 'Chest Decompression Kit (10g - 12g, 3" Needle)', '1 kit',
  'compliance', true, false, 'deficiency', false, 46, 170
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=30
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R047', 'End-Tidal CO2 (ETCO2) Detectors (In-Line & Nasal)', '1 each size',
  'compliance', true, false, 'deficiency', false, 47, 180
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=30
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R052', 'Blood Pressure Cuffs w/ Gauge (Infant, Child, Adult, Lg Adult)', '1 set (4 sizes)',
  'compliance', true, false, 'deficiency', false, 52, 10
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=40
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R053', 'Stethoscopes', '1',
  'compliance', true, false, 'deficiency', false, 53, 20
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=40
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R054', 'Assessment Flashlights / Penlights', '1',
  'compliance', true, false, 'deficiency', false, 54, 30
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=40
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R055', 'Clinical Thermometer', '1',
  'compliance', true, false, 'deficiency', false, 55, 40
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=40
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R056', 'Blood Glucose Measuring Kit (Meter, Strips, Lancets, Reagent)', '1 kit',
  'compliance', true, false, 'deficiency', false, 56, 50
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=40
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R057', 'Blood Glucose Test Strip Bottles (Extra)', '1 bottle',
  'compliance', true, false, 'deficiency', false, 57, 60
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=40
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R058', 'Pulse Oximeter w/ Adult & Pediatric Sensors', '1 set sensors',
  'compliance', true, false, 'deficiency', false, 58, 70
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=40
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R060', 'Cervical Collars, Adjustable / Rigid', '1 each (3 sizes)',
  'compliance', true, false, 'deficiency', false, 60, 10
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=50
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R061', 'Long Spine Backboard w/ 3 Sets Torso Straps', '1 optional',
  'compliance', true, false, 'deficiency', false, 61, 20
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=50
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R063', 'Lower Extremity Traction Splint (Adult & Pediatric)', '1 adult',
  'compliance', true, false, 'deficiency', false, 63, 40
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=50
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R064', 'Extremity Splints (Adult Long/Short, Peds Long/Short)', '1 each (4 sizes)',
  'compliance', true, false, 'deficiency', false, 64, 50
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=50
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R065', 'Triangular Bandages / Slings', '2',
  'compliance', true, false, 'deficiency', false, 65, 60
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=50
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R066', 'Lateral Head Immobilization Device', '1 optional',
  'compliance', true, false, 'deficiency', false, 66, 70
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=50
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R070', 'Commercial Arterial Tourniquets (Hemorrhage Control)', '2',
  'compliance', true, false, 'deficiency', false, 70, 10
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=60
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R071', 'Sterile Gauze Pads (4" x 4", Single Packages)', '10',
  'compliance', true, false, 'deficiency', false, 71, 20
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=60
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R072', 'Trauma Dressings / Universal Dressings (12" x 30")', '2',
  'compliance', true, false, 'deficiency', false, 72, 30
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=60
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R073', 'Soft Roller Bandages (4" Kerlix Rolls)', '4',
  'compliance', true, false, 'deficiency', false, 73, 40
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=60
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R074', 'Occlusive Vaseline Gauze (3" x 8") / Vented Chest Seal', '1',
  'compliance', true, false, 'deficiency', false, 74, 50
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=60
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R075', 'Adhesive Tape Rolls (Paper or Plastic)', '2',
  'compliance', true, false, 'deficiency', false, 75, 60
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=60
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R076', 'Saran Wrap (Burn Treatment)', '1',
  'compliance', true, false, 'deficiency', false, 76, 70
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=60
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R077', 'Adhesive Band-Aids', '10',
  'compliance', true, false, 'deficiency', false, 77, 80
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=60
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R078', 'Burn Sheets (Clean, Individually Wrapped)', '1',
  'compliance', true, false, 'deficiency', false, 78, 90
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=60
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R079', 'Heavy-Duty Bandage Shears / Scissors', '1',
  'compliance', true, false, 'deficiency', false, 79, 100
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=60
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R080', 'Pour Bottles 0.9% Normal Saline (1000 mL)', '1',
  'compliance', true, false, 'deficiency', false, 80, 110
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=60
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R081', 'Pour Bottles Sterile Water (1000 mL)', '1',
  'compliance', true, false, 'deficiency', false, 81, 120
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=60
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R083', 'Mass Trauma Bag (BLS / ALS System Standard)', '1 ALS Bag',
  'compliance', true, false, 'deficiency', false, 83, 10
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=70
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R084', 'Wrecking Bar (24" or Larger)', '1',
  'compliance', true, false, 'deficiency', false, 84, 20
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=70
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R085', 'Safety Goggles', '2',
  'compliance', true, false, 'deficiency', false, 85, 30
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=70
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R086', '5# ABC Fire Extinguishers w/ Tag', '2',
  'compliance', true, false, 'deficiency', false, 86, 40
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=70
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R087', 'Roadside Warning Devices (Reflective / Illuminated)', '1 set',
  'compliance', true, false, 'deficiency', false, 87, 50
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=70
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R091', 'Manual 12-Lead Cardiac Monitor / Defibrillator / Pacemaker', '1 monitor',
  'compliance', true, false, 'deficiency', false, 91, 20
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=80
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R092', 'Adult Defibrillator / Pacing Pads', '1 set',
  'compliance', true, false, 'deficiency', false, 92, 30
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=80
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R093', 'Pediatric Defibrillator / Pacing Pads', '1 set',
  'compliance', true, false, 'deficiency', false, 93, 40
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=80
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R094', 'Adult EKG Electrodes', '15',
  'compliance', true, false, 'deficiency', false, 94, 50
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=80
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R095', 'Pediatric EKG Electrodes', '10',
  'compliance', true, false, 'deficiency', false, 95, 60
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=80
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R096', 'EKG Tracing Paper Rolls', '1',
  'compliance', true, false, 'deficiency', false, 96, 70
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=80
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R097', 'Round ICD Magnet', '1',
  'compliance', true, false, 'deficiency', false, 97, 80
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=80
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R099', '100-mL IV Bags (0.9% Normal Saline)', '1 bag',
  'compliance', true, false, 'deficiency', false, 99, 10
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=90
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R100', '1000-mL IV Bags (0.9% Normal Saline)', '2 bags',
  'compliance', true, false, 'deficiency', false, 100, 20
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=90
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R101', 'Infusion Sets (Macro Drip)', '2',
  'compliance', true, false, 'deficiency', false, 101, 30
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=90
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R102', 'Infusion Sets (Mini Drip)', '1',
  'compliance', true, false, 'deficiency', false, 102, 40
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=90
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R103', 'Filter Tubing (22-Micron Filter)', '1',
  'compliance', true, false, 'deficiency', false, 103, 50
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=90
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R104', 'IV Over-Needle Catheters (14g - 24g, 2 Each Size)', '12 catheters',
  'compliance', true, false, 'deficiency', false, 104, 60
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=90
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R105', 'Alcohol Prep Pads', '5',
  'compliance', true, false, 'deficiency', false, 105, 70
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=90
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R106', 'IV Start Kits / Supplies', '2 kits',
  'compliance', true, false, 'deficiency', false, 106, 80
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=90
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R107', 'EZ-IO Intraosseous Drill & Needles (15mm, 25mm, 40mm)', '1 set optional',
  'compliance', true, false, 'deficiency', false, 107, 90
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=90
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R108', 'Pressure Infusers (1000cc)', '1',
  'compliance', true, false, 'deficiency', false, 108, 100
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=90
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R112', 'Albuterol 2.5mg/3mL (Inhalation Solution)', '10 mg (4 doses)',
  'compliance', true, false, 'deficiency', false, 112, 10
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R113', 'Aspirin 81mg Chewable Tablets', '648 mg (8 tabs)',
  'compliance', true, false, 'deficiency', false, 113, 20
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R114', 'Diphenhydramine (Benadryl) 50mg Vial', '50 mg',
  'compliance', true, false, 'deficiency', false, 114, 30
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R115', 'Epinephrine 1mg/mL (1:1,000 Ampules/Vials)', '2 mg (2 amp)',
  'compliance', true, false, 'deficiency', false, 115, 40
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R116', 'Epinephrine 1mg/10mL (1:10,000 Cardiac Preloads)', '3 mg (3 pre)',
  'compliance', true, false, 'deficiency', false, 116, 50
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R117', 'Glucagon 1mg Injectable Kit', '1 mg',
  'compliance', true, false, 'deficiency', false, 117, 60
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R118', 'Oral Glucose Gel (15g Tubes)', '30 g (2 tubes)',
  'compliance', true, false, 'deficiency', false, 118, 70
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R119', 'Ipratropium Bromide (Atrovent) 0.02%', '1.0 mg (2 doses)',
  'compliance', true, false, 'deficiency', false, 119, 80
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R120', 'Naloxone (Narcan) 2mg/2mL Preloads', '4 mg (2 pre)',
  'compliance', true, false, 'deficiency', false, 120, 90
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R121', 'Nitroglycerin SL Tablets (Bottle)', '1 bottle',
  'compliance', true, false, 'deficiency', false, 121, 100
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R122', 'Ondansetron (Zofran) 4mg Oral Dissolve Tabs', '4 mg (1 tab)',
  'compliance', true, false, 'deficiency', false, 122, 110
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R123', 'Adenosine 6mg Vials', '18 mg (3 vials)',
  'compliance', true, false, 'deficiency', false, 123, 120
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R124', 'Amiodarone 150mg Vials', '300 mg (2 vials)',
  'compliance', true, false, 'deficiency', false, 124, 130
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R125', 'Atropine Sulfate 1mg Preloads', '2 mg (2 pre)',
  'compliance', true, false, 'deficiency', false, 125, 140
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R126', 'Dextrose 10% (D10W) 250mL IV Bags', '50 g (2 bags)',
  'compliance', true, false, 'deficiency', false, 126, 150
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R127', 'Etomidate 20mg Vials', '40 mg (2 vials)',
  'compliance', true, false, 'deficiency', false, 127, 160
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R128', 'Fentanyl 100mcg Vials (Controlled Substance)', '100 mcg (1 vial)',
  'compliance', true, false, 'deficiency', false, 128, 170
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R129', 'Ketamine 500mg Vials (Controlled Substance)', '500 mg (1 vial)',
  'compliance', true, false, 'deficiency', false, 129, 180
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R130', 'Lidocaine 100mg Preloads', '100 mg (1 pre)',
  'compliance', true, false, 'deficiency', false, 130, 190
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R131', 'Magnesium Sulfate 2g IVPB / Vials', '2 g (1 IVPB)',
  'compliance', true, false, 'deficiency', false, 131, 200
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R132', 'Midazolam (Versed) (Controlled Substance)', '20 mg total',
  'compliance', true, false, 'deficiency', false, 132, 210
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R133', 'Norepinephrine (Levophed) 4mg Vials', '4 mg (1 vial)',
  'compliance', true, false, 'deficiency', false, 133, 220
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R134', 'Sodium Bicarbonate 8.4% 50mEq Preloads', '50 mEq (1 pre)',
  'compliance', true, false, 'deficiency', false, 134, 230
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R135', 'Tranexamic Acid (TXA) 1g Vials', '1 g (1 vial)',
  'compliance', true, false, 'deficiency', false, 135, 240
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R136', 'Verapamil 5mg Vials', '5 mg (1 vial)',
  'compliance', true, false, 'deficiency', false, 136, 250
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R145', 'Broselow Length-Based Assessment Tape', '1',
  'compliance', true, false, 'deficiency', false, 145, 10
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=110
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R146', 'Pediatric Trauma Score Reference', '1',
  'compliance', true, false, 'deficiency', false, 146, 20
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=110
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R147', 'Silver Swaddler & Newborn Head Cover', '1 each',
  'compliance', true, false, 'deficiency', false, 147, 30
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=110
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R148', 'Sterile Obstetrical Kit w/ Bulb Syringe', '1 kit',
  'compliance', true, false, 'deficiency', false, 148, 40
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=110
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R149', 'Disaster Triage Tags (SMART Tags - 20 w/ START/JumpSTART)', '1 kit (20)',
  'compliance', true, false, 'deficiency', false, 149, 50
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=110
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R150', 'Ambulance Patient Care Run Report Backups (Paper)', '5',
  'compliance', true, false, 'deficiency', false, 150, 60
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=110
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R151', 'GEA Standing Medical Orders (SMO Printed Copy)', '1',
  'compliance', true, false, 'deficiency', false, 151, 70
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=110
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R152', 'Blankets (Mylar or Cloth)', '1',
  'compliance', true, false, 'deficiency', false, 152, 80
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=110
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R153', 'Sheets & Towels', '2 towels',
  'compliance', true, false, 'deficiency', false, 153, 90
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=110
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R155', 'Cold Packs / Thermal Packs', '2 cold / 2 warm',
  'compliance', true, false, 'deficiency', false, 155, 110
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=110
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R156', 'PPE (Gloves, Gowns, Masks, Eye Protection, Biohazard Bags)', 'Required',
  'compliance', true, false, 'deficiency', false, 156, 120
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=110
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R157', 'ANSI Reflective Vests', '1 / provider',
  'compliance', true, false, 'deficiency', false, 157, 130
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=110
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R158', 'Sharps Container & Ampule Breaker', '1 sharps, 2 amp',
  'compliance', true, false, 'deficiency', false, 158, 140
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=110
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R159', 'Chemical Disinfectants (Hand Cleanser & Surface Cleaner)', '1 each',
  'compliance', true, false, 'deficiency', false, 159, 150
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_NON_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=110
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_templates(
  code, name, description, inspection_type_id, vehicle_type_id, scope_type, agency_id, active
)
select 'GEA_ALS_AMBULANCE_EQUIPMENT', 'GEA ALS Ambulance Equipment Inspection',
  'System inspection template seeded from gea-idph-ems-comparison-matrix.xlsx.',
  it.id, vt.id, 'system', null, true
from public.inspection_types it
join public.vehicle_types vt on vt.code = 'GEA_ALS_AMBULANCE'
where it.code = 'GEAEMS_VEHICLE_INSPECTION'
on conflict (code) do update
set name = excluded.name, description = excluded.description,
    inspection_type_id = excluded.inspection_type_id,
    vehicle_type_id = excluded.vehicle_type_id, active = true;

insert into public.inspection_form_versions(template_id, version_number, status, source_name, published_at)
select t.id, 1, 'published', 'gea-idph-ems-comparison-matrix.xlsx', now()
from public.inspection_form_templates t
where t.code = 'GEA_ALS_AMBULANCE_EQUIPMENT'
on conflict (template_id, version_number) do update
set status='published', source_name=excluded.source_name,
    published_at=coalesce(public.inspection_form_versions.published_at, excluded.published_at);

insert into public.inspection_form_sections(form_version_id, title, sort_order)
select v.id, '1. VEHICLE HARDWARE, CHASSIS & REGULATORY COMPLIANCE', 10
from public.inspection_form_versions v
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1
on conflict (form_version_id, sort_order) do update set title=excluded.title;

insert into public.inspection_form_sections(form_version_id, title, sort_order)
select v.id, '2. OXYGEN & SUCTION EQUIPMENT', 20
from public.inspection_form_versions v
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1
on conflict (form_version_id, sort_order) do update set title=excluded.title;

insert into public.inspection_form_sections(form_version_id, title, sort_order)
select v.id, '3. AIRWAY MANAGEMENT, VENTILATION & RESUSCITATION', 30
from public.inspection_form_versions v
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1
on conflict (form_version_id, sort_order) do update set title=excluded.title;

insert into public.inspection_form_sections(form_version_id, title, sort_order)
select v.id, '4. PATIENT ASSESSMENT & DIAGNOSTICS', 40
from public.inspection_form_versions v
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1
on conflict (form_version_id, sort_order) do update set title=excluded.title;

insert into public.inspection_form_sections(form_version_id, title, sort_order)
select v.id, '5. IMMOBILIZATION & SPINAL CARE', 50
from public.inspection_form_versions v
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1
on conflict (form_version_id, sort_order) do update set title=excluded.title;

insert into public.inspection_form_sections(form_version_id, title, sort_order)
select v.id, '6. BANDAGES, DRESSINGS & SURGICAL SUPPLIES', 60
from public.inspection_form_versions v
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1
on conflict (form_version_id, sort_order) do update set title=excluded.title;

insert into public.inspection_form_sections(form_version_id, title, sort_order)
select v.id, '7. MASS TRAUMA KITS & EXTRICATION GEAR', 70
from public.inspection_form_versions v
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1
on conflict (form_version_id, sort_order) do update set title=excluded.title;

insert into public.inspection_form_sections(form_version_id, title, sort_order)
select v.id, '8. CARDIAC MONITORING & RESUSCITATION HARDWARE', 80
from public.inspection_form_versions v
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1
on conflict (form_version_id, sort_order) do update set title=excluded.title;

insert into public.inspection_form_sections(form_version_id, title, sort_order)
select v.id, '9. INTRAVENOUS ACCESS, VASCULAR SUPPLIES & PUMPS', 90
from public.inspection_form_versions v
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1
on conflict (form_version_id, sort_order) do update set title=excluded.title;

insert into public.inspection_form_sections(form_version_id, title, sort_order)
select v.id, '10. EMERGENCY MEDICATIONS & FORMULARY (TOTAL REQUIRED UNITS)', 100
from public.inspection_form_versions v
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1
on conflict (form_version_id, sort_order) do update set title=excluded.title;

insert into public.inspection_form_sections(form_version_id, title, sort_order)
select v.id, '11. PEDIATRIC, FORMS & MISCELLANEOUS SUPPLIES', 110
from public.inspection_form_versions v
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1
on conflict (form_version_id, sort_order) do update set title=excluded.title;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R003', 'Primary Patient Cot', '1',
  'compliance', true, false, 'deficiency', false, 3, 10
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=10
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R004', 'Secondary Patient Stretcher', '1',
  'compliance', true, false, 'deficiency', false, 4, 20
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=10
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R005', 'IDOT Safety Inspection Sticker (Current & Valid)', '1',
  'compliance', true, false, 'deficiency', false, 5, 30
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=10
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R006', 'IDPH Central Complaint Registry Sticker', '1',
  'compliance', true, false, 'deficiency', false, 6, 40
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=10
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R007', 'FCC Radio License (On File)', 'Required',
  'compliance', true, false, 'deficiency', false, 7, 50
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=10
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R008', 'MERCI / VHF Communications Radio', '1 (VHF)',
  'compliance', true, false, 'deficiency', false, 8, 60
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=10
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R009', 'Telemetry Radio / Cellular Phone', '1',
  'compliance', true, false, 'deficiency', false, 9, 70
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=10
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R010', '12-Lead ECG Transmission Capability', '1',
  'compliance', true, false, 'deficiency', false, 10, 80
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=10
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R011', 'Electric Clock w/ Sweep Second Hand', '1',
  'compliance', true, false, 'deficiency', false, 11, 90
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=10
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R013', 'On-Board Oxygen Cylinder (Main System)', '1',
  'compliance', true, false, 'deficiency', false, 13, 10
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=20
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R014', 'Portable Oxygen Cylinder (w/ Regulator & Key)', '1',
  'compliance', true, false, 'deficiency', false, 14, 20
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=20
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R015', 'Spare Oxygen D or E Cylinder', '1',
  'compliance', true, false, 'deficiency', false, 15, 30
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=20
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R016', 'Oxygen Delivery Tubing', '2',
  'compliance', true, false, 'deficiency', false, 16, 40
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=20
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R017', 'Non-Rebreather Oxygen Masks (Adult)', '2',
  'compliance', true, false, 'deficiency', false, 17, 50
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=20
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R018', 'Non-Rebreather Oxygen Masks (Child/Pediatric)', '2',
  'compliance', true, false, 'deficiency', false, 18, 60
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=20
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R019', 'Non-Rebreather Oxygen Masks (Infant)', '2',
  'compliance', true, false, 'deficiency', false, 19, 70
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=20
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R020', 'Nasal Cannula (Adult)', '3',
  'compliance', true, false, 'deficiency', false, 20, 80
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=20
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R021', 'Nasal Cannula (Pediatric)', '3',
  'compliance', true, false, 'deficiency', false, 21, 90
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=20
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R022', 'On-Board Suction System', '1',
  'compliance', true, false, 'deficiency', false, 22, 100
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=20
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R023', 'Portable Suction Unit', '1',
  'compliance', true, false, 'deficiency', false, 23, 110
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=20
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R024', 'Suction Tubing', '3',
  'compliance', true, false, 'deficiency', false, 24, 120
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=20
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R025', 'Sterile Suction Catheters (6F - 18F)', '2 each size',
  'compliance', true, false, 'deficiency', false, 25, 130
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=20
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R026', 'Semi-Rigid Pharyngeal / Tonsil Tip Suction Catheters', '3',
  'compliance', true, false, 'deficiency', false, 26, 140
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=20
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R027', 'DuCanto Rigid Suction Catheter (9.3" x 0.26")', '1',
  'compliance', true, false, 'deficiency', false, 27, 150
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=20
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R028', 'Sterile Suction Kit', '1',
  'compliance', true, false, 'deficiency', false, 28, 160
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=20
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R030', 'Oropharyngeal Airways (OPAs, Sizes 40mm - 100mm)', '1 each (7 sizes)',
  'compliance', true, false, 'deficiency', false, 30, 10
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=30
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R031', 'Nasopharyngeal Airways (NPAs, Sizes 12F - 34F w/ Lube)', '1 each (12 sizes)',
  'compliance', true, false, 'deficiency', false, 31, 20
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=30
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R032', 'Adult Bag-Valve-Mask (BVM) w/ Transparent Mask', '1',
  'compliance', true, false, 'deficiency', false, 32, 30
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=30
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R033', 'Pediatric Bag-Valve-Mask (BVM) w/ Child Mask', '1',
  'compliance', true, false, 'deficiency', false, 33, 40
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=30
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R034', 'Neonatal / Infant Bag-Valve-Mask (BVM) w/ Mask', '1',
  'compliance', true, false, 'deficiency', false, 34, 50
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=30
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R035', 'Aerosol Masks (Adult & Pediatric)', '2 each',
  'compliance', true, false, 'deficiency', false, 35, 60
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=30
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R036', 'Hand-Held Nebulizers w/ Adapters', '2',
  'compliance', true, false, 'deficiency', false, 36, 70
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=30
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R037', 'CPAP Flow Safe II w/ Nebulizer (Large)', '1',
  'compliance', true, false, 'deficiency', false, 37, 80
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=30
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R038', 'i-Gel / i-Gel O2 Supraglottic Airways (Sizes 1.5 - 5)', '1 each size',
  'compliance', true, false, 'deficiency', false, 38, 90
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=30
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R039', 'Endotracheal Tubes (ETTs, Sizes 3.0 - 8.5)', '1 set (12 sizes)',
  'compliance', true, false, 'deficiency', false, 39, 100
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=30
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R040', 'Laryngoscope Handles (Adult & Pediatric)', '1 each',
  'compliance', true, false, 'deficiency', false, 40, 110
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=30
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R041', 'Fiberoptic Laryngoscope Blades (Miller 1-4, Mac 2-4)', '1 set',
  'compliance', true, false, 'deficiency', false, 41, 120
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=30
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R042', 'Endotracheal Intubation Stylets (Adult & Pediatric)', '1 each',
  'compliance', true, false, 'deficiency', false, 42, 130
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=30
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R043', 'Intubating Bougie', '1',
  'compliance', true, false, 'deficiency', false, 43, 140
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=30
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R044', 'Magill Forceps (Adult & Pediatric)', '1 each',
  'compliance', true, false, 'deficiency', false, 44, 150
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=30
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R045', 'Surgical Cricothyrotomy Kit', '1 kit',
  'compliance', true, false, 'deficiency', false, 45, 160
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=30
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R046', 'Chest Decompression Kit (10g - 12g, 3" Needle)', '1 kit',
  'compliance', true, false, 'deficiency', false, 46, 170
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=30
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R047', 'End-Tidal CO2 (ETCO2) Detectors (In-Line & Nasal)', '1 each size',
  'compliance', true, false, 'deficiency', false, 47, 180
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=30
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R052', 'Blood Pressure Cuffs w/ Gauge (Infant, Child, Adult, Lg Adult)', '1 set (4 sizes)',
  'compliance', true, false, 'deficiency', false, 52, 10
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=40
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R053', 'Stethoscopes', '2',
  'compliance', true, false, 'deficiency', false, 53, 20
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=40
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R054', 'Assessment Flashlights / Penlights', '2',
  'compliance', true, false, 'deficiency', false, 54, 30
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=40
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R055', 'Clinical Thermometer', '1',
  'compliance', true, false, 'deficiency', false, 55, 40
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=40
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R056', 'Blood Glucose Measuring Kit (Meter, Strips, Lancets, Reagent)', '1 kit',
  'compliance', true, false, 'deficiency', false, 56, 50
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=40
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R057', 'Blood Glucose Test Strip Bottles (Extra)', '2 bottles',
  'compliance', true, false, 'deficiency', false, 57, 60
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=40
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R058', 'Pulse Oximeter w/ Adult & Pediatric Sensors', '1 set sensors',
  'compliance', true, false, 'deficiency', false, 58, 70
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=40
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R060', 'Cervical Collars, Adjustable / Rigid', '5 total',
  'compliance', true, false, 'deficiency', false, 60, 10
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=50
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R061', 'Long Spine Backboard w/ 3 Sets Torso Straps', '2 boards + 6 straps',
  'compliance', true, false, 'deficiency', false, 61, 20
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=50
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R062', 'Short Spine Board or KED Extrication Device', '1 device',
  'compliance', true, false, 'deficiency', false, 62, 30
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=50
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R063', 'Lower Extremity Traction Splint (Adult & Pediatric)', '1 adult & peds',
  'compliance', true, false, 'deficiency', false, 63, 40
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=50
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R064', 'Extremity Splints (Adult Long/Short, Peds Long/Short)', '2 each (8 sizes)',
  'compliance', true, false, 'deficiency', false, 64, 50
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=50
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R065', 'Triangular Bandages / Slings', '5',
  'compliance', true, false, 'deficiency', false, 65, 60
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=50
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R066', 'Lateral Head Immobilization Device', '2 set',
  'compliance', true, false, 'deficiency', false, 66, 70
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=50
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R068', 'Medical Grade Limb Restraints (Sets)', '1 set per limb',
  'compliance', true, false, 'deficiency', false, 68, 90
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=50
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R070', 'Commercial Arterial Tourniquets (Hemorrhage Control)', '2',
  'compliance', true, false, 'deficiency', false, 70, 10
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=60
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R071', 'Sterile Gauze Pads (4" x 4", Single Packages)', '20',
  'compliance', true, false, 'deficiency', false, 71, 20
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=60
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R072', 'Trauma Dressings / Universal Dressings (12" x 30")', '6',
  'compliance', true, false, 'deficiency', false, 72, 30
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=60
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R073', 'Soft Roller Bandages (4" Kerlix Rolls)', '10',
  'compliance', true, false, 'deficiency', false, 73, 40
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=60
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R074', 'Occlusive Vaseline Gauze (3" x 8") / Vented Chest Seal', '2',
  'compliance', true, false, 'deficiency', false, 74, 50
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=60
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R075', 'Adhesive Tape Rolls (Paper or Plastic)', '2',
  'compliance', true, false, 'deficiency', false, 75, 60
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=60
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R076', 'Saran Wrap (Burn Treatment)', '1',
  'compliance', true, false, 'deficiency', false, 76, 70
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=60
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R077', 'Adhesive Band-Aids', '10',
  'compliance', true, false, 'deficiency', false, 77, 80
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=60
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R078', 'Burn Sheets (Clean, Individually Wrapped)', '2',
  'compliance', true, false, 'deficiency', false, 78, 90
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=60
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R079', 'Heavy-Duty Bandage Shears / Scissors', '1',
  'compliance', true, false, 'deficiency', false, 79, 100
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=60
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R080', 'Pour Bottles 0.9% Normal Saline (1000 mL)', '2',
  'compliance', true, false, 'deficiency', false, 80, 110
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=60
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R081', 'Pour Bottles Sterile Water (1000 mL)', '1',
  'compliance', true, false, 'deficiency', false, 81, 120
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=60
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R083', 'Mass Trauma Bag (BLS / ALS System Standard)', '1 ALS Bag',
  'compliance', true, false, 'deficiency', false, 83, 10
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=70
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R084', 'Wrecking Bar (24" or Larger)', '1',
  'compliance', true, false, 'deficiency', false, 84, 20
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=70
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R085', 'Safety Goggles', '2',
  'compliance', true, false, 'deficiency', false, 85, 30
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=70
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R086', '5# ABC Fire Extinguishers w/ Tag', '2',
  'compliance', true, false, 'deficiency', false, 86, 40
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=70
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R087', 'Roadside Warning Devices (Reflective / Illuminated)', '1 set',
  'compliance', true, false, 'deficiency', false, 87, 50
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=70
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R088', 'Stair Chair / Collapsible Evacuation Chair', '1',
  'compliance', true, false, 'deficiency', false, 88, 60
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=70
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R091', 'Manual 12-Lead Cardiac Monitor / Defibrillator / Pacemaker', '1 monitor',
  'compliance', true, false, 'deficiency', false, 91, 20
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=80
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R092', 'Adult Defibrillator / Pacing Pads', '2 sets',
  'compliance', true, false, 'deficiency', false, 92, 30
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=80
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R093', 'Pediatric Defibrillator / Pacing Pads', '2 sets',
  'compliance', true, false, 'deficiency', false, 93, 40
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=80
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R094', 'Adult EKG Electrodes', '30',
  'compliance', true, false, 'deficiency', false, 94, 50
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=80
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R095', 'Pediatric EKG Electrodes', '10',
  'compliance', true, false, 'deficiency', false, 95, 60
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=80
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R096', 'EKG Tracing Paper Rolls', '2',
  'compliance', true, false, 'deficiency', false, 96, 70
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=80
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R097', 'Round ICD Magnet', '1',
  'compliance', true, false, 'deficiency', false, 97, 80
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=80
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R099', '100-mL IV Bags (0.9% Normal Saline)', '2 bags',
  'compliance', true, false, 'deficiency', false, 99, 10
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=90
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R100', '1000-mL IV Bags (0.9% Normal Saline)', '8 bags',
  'compliance', true, false, 'deficiency', false, 100, 20
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=90
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R101', 'Infusion Sets (Macro Drip)', '3',
  'compliance', true, false, 'deficiency', false, 101, 30
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=90
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R102', 'Infusion Sets (Mini Drip)', '1',
  'compliance', true, false, 'deficiency', false, 102, 40
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=90
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R103', 'Filter Tubing (22-Micron Filter)', '1',
  'compliance', true, false, 'deficiency', false, 103, 50
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=90
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R104', 'IV Over-Needle Catheters (14g - 24g, 2 Each Size)', '12 catheters',
  'compliance', true, false, 'deficiency', false, 104, 60
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=90
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R105', 'Alcohol Prep Pads', '20',
  'compliance', true, false, 'deficiency', false, 105, 70
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=90
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R106', 'IV Start Kits / Supplies', '3 kits',
  'compliance', true, false, 'deficiency', false, 106, 80
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=90
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R107', 'EZ-IO Intraosseous Drill & Needles (15mm, 25mm, 40mm)', '1 set',
  'compliance', true, false, 'deficiency', false, 107, 90
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=90
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R108', 'Pressure Infusers (1000cc)', '2',
  'compliance', true, false, 'deficiency', false, 108, 100
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=90
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R112', 'Albuterol 2.5mg/3mL (Inhalation Solution)', '20 mg (8 doses)',
  'compliance', true, false, 'deficiency', false, 112, 10
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R113', 'Aspirin 81mg Chewable Tablets', '648 mg (8 tabs)',
  'compliance', true, false, 'deficiency', false, 113, 20
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R114', 'Diphenhydramine (Benadryl) 50mg Vial', '50 mg',
  'compliance', true, false, 'deficiency', false, 114, 30
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R115', 'Epinephrine 1mg/mL (1:1,000 Ampules/Vials)', '4 mg (4 amp)',
  'compliance', true, false, 'deficiency', false, 115, 40
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R116', 'Epinephrine 1mg/10mL (1:10,000 Cardiac Preloads)', '9 mg (9 pre)',
  'compliance', true, false, 'deficiency', false, 116, 50
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R117', 'Glucagon 1mg Injectable Kit', '1 mg',
  'compliance', true, false, 'deficiency', false, 117, 60
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R118', 'Oral Glucose Gel (15g Tubes)', '30 g (2 tubes)',
  'compliance', true, false, 'deficiency', false, 118, 70
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R119', 'Ipratropium Bromide (Atrovent) 0.02%', '2.0 mg (4 doses)',
  'compliance', true, false, 'deficiency', false, 119, 80
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R120', 'Naloxone (Narcan) 2mg/2mL Preloads', '8 mg (4 pre)',
  'compliance', true, false, 'deficiency', false, 120, 90
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R121', 'Nitroglycerin SL Tablets (Bottle)', '1 bottle',
  'compliance', true, false, 'deficiency', false, 121, 100
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R122', 'Ondansetron (Zofran) 4mg Oral Dissolve Tabs', '8 mg (2 tabs)',
  'compliance', true, false, 'deficiency', false, 122, 110
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R123', 'Adenosine 6mg Vials', '18 mg (3 vials)',
  'compliance', true, false, 'deficiency', false, 123, 120
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R124', 'Amiodarone 150mg Vials', '450 mg (3 vials)',
  'compliance', true, false, 'deficiency', false, 124, 130
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R125', 'Atropine Sulfate 1mg Preloads', '6 mg (6 pre)',
  'compliance', true, false, 'deficiency', false, 125, 140
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R126', 'Dextrose 10% (D10W) 250mL IV Bags', '50 g (2 bags)',
  'compliance', true, false, 'deficiency', false, 126, 150
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R127', 'Etomidate 20mg Vials', '40 mg (2 vials)',
  'compliance', true, false, 'deficiency', false, 127, 160
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R128', 'Fentanyl 100mcg Vials (Controlled Substance)', '300 mcg (3 vials)',
  'compliance', true, false, 'deficiency', false, 128, 170
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R129', 'Ketamine 500mg Vials (Controlled Substance)', '500 mg (1 vial)',
  'compliance', true, false, 'deficiency', false, 129, 180
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R130', 'Lidocaine 100mg Preloads', '200 mg (2 pre)',
  'compliance', true, false, 'deficiency', false, 130, 190
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R131', 'Magnesium Sulfate 2g IVPB / Vials', '4 g (2 IVPB)',
  'compliance', true, false, 'deficiency', false, 131, 200
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R132', 'Midazolam (Versed) (Controlled Substance)', '30 mg total',
  'compliance', true, false, 'deficiency', false, 132, 210
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R133', 'Norepinephrine (Levophed) 4mg Vials', '4 mg (1 vial)',
  'compliance', true, false, 'deficiency', false, 133, 220
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R134', 'Sodium Bicarbonate 8.4% 50mEq Preloads', '100 mEq (2 pre)',
  'compliance', true, false, 'deficiency', false, 134, 230
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R135', 'Tranexamic Acid (TXA) 1g Vials', '1 g (1 vial)',
  'compliance', true, false, 'deficiency', false, 135, 240
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R136', 'Verapamil 5mg Vials', '10 mg (2 vials)',
  'compliance', true, false, 'deficiency', false, 136, 250
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R137', 'Zofran 4mg/2mL IV Vials', '8 mg (2 vials)',
  'compliance', true, false, 'deficiency', false, 137, 260
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R138', 'Tetracaine 0.5% Ophthalmic Eye Drops', '1 bottle',
  'compliance', true, false, 'deficiency', false, 138, 270
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R145', 'Broselow Length-Based Assessment Tape', '1',
  'compliance', true, false, 'deficiency', false, 145, 10
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=110
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R146', 'Pediatric Trauma Score Reference', '1',
  'compliance', true, false, 'deficiency', false, 146, 20
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=110
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R147', 'Silver Swaddler & Newborn Head Cover', '1 each',
  'compliance', true, false, 'deficiency', false, 147, 30
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=110
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R148', 'Sterile Obstetrical Kit w/ Bulb Syringe', '1 kit',
  'compliance', true, false, 'deficiency', false, 148, 40
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=110
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R149', 'Disaster Triage Tags (SMART Tags - 20 w/ START/JumpSTART)', '1 kit (20)',
  'compliance', true, false, 'deficiency', false, 149, 50
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=110
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R150', 'Ambulance Patient Care Run Report Backups (Paper)', '10',
  'compliance', true, false, 'deficiency', false, 150, 60
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=110
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R151', 'GEA Standing Medical Orders (SMO Printed Copy)', '1',
  'compliance', true, false, 'deficiency', false, 151, 70
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=110
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R152', 'Blankets (Mylar or Cloth)', '2',
  'compliance', true, false, 'deficiency', false, 152, 80
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=110
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R153', 'Sheets & Towels', '2 sheets, 2 towels',
  'compliance', true, false, 'deficiency', false, 153, 90
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=110
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R154', 'Urinal & Bedpan', '1 each',
  'compliance', true, false, 'deficiency', false, 154, 100
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=110
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R155', 'Cold Packs / Thermal Packs', '8 cold / 3 warm',
  'compliance', true, false, 'deficiency', false, 155, 110
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=110
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R156', 'PPE (Gloves, Gowns, Masks, Eye Protection, Biohazard Bags)', 'Required',
  'compliance', true, false, 'deficiency', false, 156, 120
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=110
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R157', 'ANSI Reflective Vests', '1 / provider',
  'compliance', true, false, 'deficiency', false, 157, 130
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=110
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R158', 'Sharps Container & Ampule Breaker', '1 sharps, 2 amp',
  'compliance', true, false, 'deficiency', false, 158, 140
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=110
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R159', 'Chemical Disinfectants (Hand Cleanser & Surface Cleaner)', '1 each',
  'compliance', true, false, 'deficiency', false, 159, 150
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_ALS_AMBULANCE_EQUIPMENT' and v.version_number=1 and s.sort_order=110
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_templates(
  code, name, description, inspection_type_id, vehicle_type_id, scope_type, agency_id, active
)
select 'GEA_CC_TRANSPORT_EQUIPMENT', 'GEA Critical Care Transport Equipment Inspection',
  'System inspection template seeded from gea-idph-ems-comparison-matrix.xlsx.',
  it.id, vt.id, 'system', null, true
from public.inspection_types it
join public.vehicle_types vt on vt.code = 'GEA_CC_TRANSPORT'
where it.code = 'GEAEMS_VEHICLE_INSPECTION'
on conflict (code) do update
set name = excluded.name, description = excluded.description,
    inspection_type_id = excluded.inspection_type_id,
    vehicle_type_id = excluded.vehicle_type_id, active = true;

insert into public.inspection_form_versions(template_id, version_number, status, source_name, published_at)
select t.id, 1, 'published', 'gea-idph-ems-comparison-matrix.xlsx', now()
from public.inspection_form_templates t
where t.code = 'GEA_CC_TRANSPORT_EQUIPMENT'
on conflict (template_id, version_number) do update
set status='published', source_name=excluded.source_name,
    published_at=coalesce(public.inspection_form_versions.published_at, excluded.published_at);

insert into public.inspection_form_sections(form_version_id, title, sort_order)
select v.id, '1. VEHICLE HARDWARE, CHASSIS & REGULATORY COMPLIANCE', 10
from public.inspection_form_versions v
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1
on conflict (form_version_id, sort_order) do update set title=excluded.title;

insert into public.inspection_form_sections(form_version_id, title, sort_order)
select v.id, '2. OXYGEN & SUCTION EQUIPMENT', 20
from public.inspection_form_versions v
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1
on conflict (form_version_id, sort_order) do update set title=excluded.title;

insert into public.inspection_form_sections(form_version_id, title, sort_order)
select v.id, '3. AIRWAY MANAGEMENT, VENTILATION & RESUSCITATION', 30
from public.inspection_form_versions v
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1
on conflict (form_version_id, sort_order) do update set title=excluded.title;

insert into public.inspection_form_sections(form_version_id, title, sort_order)
select v.id, '4. PATIENT ASSESSMENT & DIAGNOSTICS', 40
from public.inspection_form_versions v
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1
on conflict (form_version_id, sort_order) do update set title=excluded.title;

insert into public.inspection_form_sections(form_version_id, title, sort_order)
select v.id, '5. IMMOBILIZATION & SPINAL CARE', 50
from public.inspection_form_versions v
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1
on conflict (form_version_id, sort_order) do update set title=excluded.title;

insert into public.inspection_form_sections(form_version_id, title, sort_order)
select v.id, '6. BANDAGES, DRESSINGS & SURGICAL SUPPLIES', 60
from public.inspection_form_versions v
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1
on conflict (form_version_id, sort_order) do update set title=excluded.title;

insert into public.inspection_form_sections(form_version_id, title, sort_order)
select v.id, '7. MASS TRAUMA KITS & EXTRICATION GEAR', 70
from public.inspection_form_versions v
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1
on conflict (form_version_id, sort_order) do update set title=excluded.title;

insert into public.inspection_form_sections(form_version_id, title, sort_order)
select v.id, '8. CARDIAC MONITORING & RESUSCITATION HARDWARE', 80
from public.inspection_form_versions v
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1
on conflict (form_version_id, sort_order) do update set title=excluded.title;

insert into public.inspection_form_sections(form_version_id, title, sort_order)
select v.id, '9. INTRAVENOUS ACCESS, VASCULAR SUPPLIES & PUMPS', 90
from public.inspection_form_versions v
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1
on conflict (form_version_id, sort_order) do update set title=excluded.title;

insert into public.inspection_form_sections(form_version_id, title, sort_order)
select v.id, '10. EMERGENCY MEDICATIONS & FORMULARY (TOTAL REQUIRED UNITS)', 100
from public.inspection_form_versions v
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1
on conflict (form_version_id, sort_order) do update set title=excluded.title;

insert into public.inspection_form_sections(form_version_id, title, sort_order)
select v.id, '11. PEDIATRIC, FORMS & MISCELLANEOUS SUPPLIES', 110
from public.inspection_form_versions v
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1
on conflict (form_version_id, sort_order) do update set title=excluded.title;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R003', 'Primary Patient Cot', '1',
  'compliance', true, false, 'deficiency', false, 3, 10
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=10
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R004', 'Secondary Patient Stretcher', '1',
  'compliance', true, false, 'deficiency', false, 4, 20
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=10
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R005', 'IDOT Safety Inspection Sticker (Current & Valid)', '1',
  'compliance', true, false, 'deficiency', false, 5, 30
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=10
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R006', 'IDPH Central Complaint Registry Sticker', '1',
  'compliance', true, false, 'deficiency', false, 6, 40
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=10
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R007', 'FCC Radio License (On File)', 'Required',
  'compliance', true, false, 'deficiency', false, 7, 50
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=10
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R008', 'MERCI / VHF Communications Radio', '1 (VHF)',
  'compliance', true, false, 'deficiency', false, 8, 60
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=10
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R009', 'Telemetry Radio / Cellular Phone', '1',
  'compliance', true, false, 'deficiency', false, 9, 70
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=10
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R010', '12-Lead ECG Transmission Capability', '1',
  'compliance', true, false, 'deficiency', false, 10, 80
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=10
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R011', 'Electric Clock w/ Sweep Second Hand', '1',
  'compliance', true, false, 'deficiency', false, 11, 90
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=10
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R013', 'On-Board Oxygen Cylinder (Main System)', '1',
  'compliance', true, false, 'deficiency', false, 13, 10
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=20
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R014', 'Portable Oxygen Cylinder (w/ Regulator & Key)', '1',
  'compliance', true, false, 'deficiency', false, 14, 20
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=20
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R015', 'Spare Oxygen D or E Cylinder', '1',
  'compliance', true, false, 'deficiency', false, 15, 30
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=20
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R016', 'Oxygen Delivery Tubing', '2',
  'compliance', true, false, 'deficiency', false, 16, 40
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=20
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R017', 'Non-Rebreather Oxygen Masks (Adult)', '2',
  'compliance', true, false, 'deficiency', false, 17, 50
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=20
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R018', 'Non-Rebreather Oxygen Masks (Child/Pediatric)', '2',
  'compliance', true, false, 'deficiency', false, 18, 60
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=20
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R019', 'Non-Rebreather Oxygen Masks (Infant)', '2',
  'compliance', true, false, 'deficiency', false, 19, 70
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=20
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R020', 'Nasal Cannula (Adult)', '3',
  'compliance', true, false, 'deficiency', false, 20, 80
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=20
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R021', 'Nasal Cannula (Pediatric)', '3',
  'compliance', true, false, 'deficiency', false, 21, 90
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=20
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R022', 'On-Board Suction System', '1',
  'compliance', true, false, 'deficiency', false, 22, 100
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=20
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R023', 'Portable Suction Unit', '1',
  'compliance', true, false, 'deficiency', false, 23, 110
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=20
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R024', 'Suction Tubing', '3',
  'compliance', true, false, 'deficiency', false, 24, 120
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=20
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R025', 'Sterile Suction Catheters (6F - 18F)', '2 each size',
  'compliance', true, false, 'deficiency', false, 25, 130
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=20
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R026', 'Semi-Rigid Pharyngeal / Tonsil Tip Suction Catheters', '3',
  'compliance', true, false, 'deficiency', false, 26, 140
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=20
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R027', 'DuCanto Rigid Suction Catheter (9.3" x 0.26")', '1',
  'compliance', true, false, 'deficiency', false, 27, 150
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=20
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R028', 'Sterile Suction Kit', '1',
  'compliance', true, false, 'deficiency', false, 28, 160
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=20
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R030', 'Oropharyngeal Airways (OPAs, Sizes 40mm - 100mm)', '1 each (7 sizes)',
  'compliance', true, false, 'deficiency', false, 30, 10
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=30
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R031', 'Nasopharyngeal Airways (NPAs, Sizes 12F - 34F w/ Lube)', '1 each (12 sizes)',
  'compliance', true, false, 'deficiency', false, 31, 20
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=30
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R032', 'Adult Bag-Valve-Mask (BVM) w/ Transparent Mask', '1',
  'compliance', true, false, 'deficiency', false, 32, 30
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=30
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R033', 'Pediatric Bag-Valve-Mask (BVM) w/ Child Mask', '1',
  'compliance', true, false, 'deficiency', false, 33, 40
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=30
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R034', 'Neonatal / Infant Bag-Valve-Mask (BVM) w/ Mask', '1',
  'compliance', true, false, 'deficiency', false, 34, 50
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=30
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R035', 'Aerosol Masks (Adult & Pediatric)', '2 each',
  'compliance', true, false, 'deficiency', false, 35, 60
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=30
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R036', 'Hand-Held Nebulizers w/ Adapters', '2',
  'compliance', true, false, 'deficiency', false, 36, 70
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=30
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R037', 'CPAP Flow Safe II w/ Nebulizer (Large)', '1',
  'compliance', true, false, 'deficiency', false, 37, 80
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=30
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R038', 'i-Gel / i-Gel O2 Supraglottic Airways (Sizes 1.5 - 5)', '1 each size',
  'compliance', true, false, 'deficiency', false, 38, 90
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=30
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R039', 'Endotracheal Tubes (ETTs, Sizes 3.0 - 8.5)', '1 set (12 sizes)',
  'compliance', true, false, 'deficiency', false, 39, 100
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=30
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R040', 'Laryngoscope Handles (Adult & Pediatric)', '1 each',
  'compliance', true, false, 'deficiency', false, 40, 110
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=30
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R041', 'Fiberoptic Laryngoscope Blades (Miller 1-4, Mac 2-4)', '1 set',
  'compliance', true, false, 'deficiency', false, 41, 120
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=30
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R042', 'Endotracheal Intubation Stylets (Adult & Pediatric)', '1 each',
  'compliance', true, false, 'deficiency', false, 42, 130
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=30
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R043', 'Intubating Bougie', '1',
  'compliance', true, false, 'deficiency', false, 43, 140
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=30
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R044', 'Magill Forceps (Adult & Pediatric)', '1 each',
  'compliance', true, false, 'deficiency', false, 44, 150
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=30
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R045', 'Surgical Cricothyrotomy Kit', '1 kit',
  'compliance', true, false, 'deficiency', false, 45, 160
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=30
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R046', 'Chest Decompression Kit (10g - 12g, 3" Needle)', '1 kit',
  'compliance', true, false, 'deficiency', false, 46, 170
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=30
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R047', 'End-Tidal CO2 (ETCO2) Detectors (In-Line & Nasal)', '1 each size',
  'compliance', true, false, 'deficiency', false, 47, 180
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=30
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R048', 'Transport Ventilator w/ 3x Circuits', '1 vent + 3 circuits',
  'compliance', true, false, 'deficiency', false, 48, 190
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=30
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R049', 'H900 High-Flow Fluid Warmer w/ Heated Circuits & Cannulas', '1 unit + 2 circuits + 6 cannulas',
  'compliance', true, false, 'deficiency', false, 49, 200
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=30
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R050', 'CPR Mask w/ One-Way Safety Valve', '1',
  'compliance', true, false, 'deficiency', false, 50, 210
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=30
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R052', 'Blood Pressure Cuffs w/ Gauge (Infant, Child, Adult, Lg Adult)', '1 set (4 sizes)',
  'compliance', true, false, 'deficiency', false, 52, 10
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=40
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R053', 'Stethoscopes', '2',
  'compliance', true, false, 'deficiency', false, 53, 20
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=40
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R054', 'Assessment Flashlights / Penlights', '2',
  'compliance', true, false, 'deficiency', false, 54, 30
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=40
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R055', 'Clinical Thermometer', '1',
  'compliance', true, false, 'deficiency', false, 55, 40
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=40
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R056', 'Blood Glucose Measuring Kit (Meter, Strips, Lancets, Reagent)', '1 kit',
  'compliance', true, false, 'deficiency', false, 56, 50
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=40
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R057', 'Blood Glucose Test Strip Bottles (Extra)', '2 bottles',
  'compliance', true, false, 'deficiency', false, 57, 60
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=40
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R058', 'Pulse Oximeter w/ Adult & Pediatric Sensors', '1 set sensors',
  'compliance', true, false, 'deficiency', false, 58, 70
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=40
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R060', 'Cervical Collars, Adjustable / Rigid', '3 total',
  'compliance', true, false, 'deficiency', false, 60, 10
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=50
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R061', 'Long Spine Backboard w/ 3 Sets Torso Straps', '2 boards + 6 straps',
  'compliance', true, false, 'deficiency', false, 61, 20
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=50
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R062', 'Short Spine Board or KED Extrication Device', '1 device',
  'compliance', true, false, 'deficiency', false, 62, 30
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=50
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R063', 'Lower Extremity Traction Splint (Adult & Pediatric)', '1 adult & peds',
  'compliance', true, false, 'deficiency', false, 63, 40
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=50
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R064', 'Extremity Splints (Adult Long/Short, Peds Long/Short)', '2 each (8 sizes)',
  'compliance', true, false, 'deficiency', false, 64, 50
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=50
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R065', 'Triangular Bandages / Slings', '5',
  'compliance', true, false, 'deficiency', false, 65, 60
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=50
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R066', 'Lateral Head Immobilization Device', '2 set',
  'compliance', true, false, 'deficiency', false, 66, 70
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=50
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R068', 'Medical Grade Limb Restraints (Sets)', '1 set per limb',
  'compliance', true, false, 'deficiency', false, 68, 90
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=50
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R070', 'Commercial Arterial Tourniquets (Hemorrhage Control)', '2',
  'compliance', true, false, 'deficiency', false, 70, 10
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=60
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R071', 'Sterile Gauze Pads (4" x 4", Single Packages)', '20',
  'compliance', true, false, 'deficiency', false, 71, 20
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=60
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R072', 'Trauma Dressings / Universal Dressings (12" x 30")', '6',
  'compliance', true, false, 'deficiency', false, 72, 30
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=60
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R073', 'Soft Roller Bandages (4" Kerlix Rolls)', '10',
  'compliance', true, false, 'deficiency', false, 73, 40
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=60
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R075', 'Adhesive Tape Rolls (Paper or Plastic)', '2',
  'compliance', true, false, 'deficiency', false, 75, 60
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=60
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R076', 'Saran Wrap (Burn Treatment)', '1',
  'compliance', true, false, 'deficiency', false, 76, 70
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=60
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R077', 'Adhesive Band-Aids', '10',
  'compliance', true, false, 'deficiency', false, 77, 80
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=60
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R078', 'Burn Sheets (Clean, Individually Wrapped)', '2',
  'compliance', true, false, 'deficiency', false, 78, 90
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=60
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R079', 'Heavy-Duty Bandage Shears / Scissors', '1',
  'compliance', true, false, 'deficiency', false, 79, 100
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=60
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R080', 'Pour Bottles 0.9% Normal Saline (1000 mL)', '2',
  'compliance', true, false, 'deficiency', false, 80, 110
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=60
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R081', 'Pour Bottles Sterile Water (1000 mL)', '1',
  'compliance', true, false, 'deficiency', false, 81, 120
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=60
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R083', 'Mass Trauma Bag (BLS / ALS System Standard)', '1 ALS Bag',
  'compliance', true, false, 'deficiency', false, 83, 10
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=70
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R084', 'Wrecking Bar (24" or Larger)', '1',
  'compliance', true, false, 'deficiency', false, 84, 20
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=70
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R085', 'Safety Goggles', '2',
  'compliance', true, false, 'deficiency', false, 85, 30
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=70
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R086', '5# ABC Fire Extinguishers w/ Tag', '2',
  'compliance', true, false, 'deficiency', false, 86, 40
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=70
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R087', 'Roadside Warning Devices (Reflective / Illuminated)', '1 set',
  'compliance', true, false, 'deficiency', false, 87, 50
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=70
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R088', 'Stair Chair / Collapsible Evacuation Chair', '1',
  'compliance', true, false, 'deficiency', false, 88, 60
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=70
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R091', 'Manual 12-Lead Cardiac Monitor / Defibrillator / Pacemaker', '1 monitor',
  'compliance', true, false, 'deficiency', false, 91, 20
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=80
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R092', 'Adult Defibrillator / Pacing Pads', '2 sets',
  'compliance', true, false, 'deficiency', false, 92, 30
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=80
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R093', 'Pediatric Defibrillator / Pacing Pads', '2 sets',
  'compliance', true, false, 'deficiency', false, 93, 40
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=80
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R094', 'Adult EKG Electrodes', '30',
  'compliance', true, false, 'deficiency', false, 94, 50
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=80
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R095', 'Pediatric EKG Electrodes', '10',
  'compliance', true, false, 'deficiency', false, 95, 60
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=80
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R096', 'EKG Tracing Paper Rolls', '2',
  'compliance', true, false, 'deficiency', false, 96, 70
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=80
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R097', 'Round ICD Magnet', '1',
  'compliance', true, false, 'deficiency', false, 97, 80
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=80
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R099', '100-mL IV Bags (0.9% Normal Saline)', '2 bags',
  'compliance', true, false, 'deficiency', false, 99, 10
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=90
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R100', '1000-mL IV Bags (0.9% Normal Saline)', '8 bags',
  'compliance', true, false, 'deficiency', false, 100, 20
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=90
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R101', 'Infusion Sets (Macro Drip)', '3',
  'compliance', true, false, 'deficiency', false, 101, 30
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=90
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R102', 'Infusion Sets (Mini Drip)', '1',
  'compliance', true, false, 'deficiency', false, 102, 40
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=90
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R103', 'Filter Tubing (22-Micron Filter)', '1',
  'compliance', true, false, 'deficiency', false, 103, 50
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=90
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R104', 'IV Over-Needle Catheters (14g - 24g, 2 Each Size)', '12 catheters',
  'compliance', true, false, 'deficiency', false, 104, 60
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=90
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R105', 'Alcohol Prep Pads', '20',
  'compliance', true, false, 'deficiency', false, 105, 70
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=90
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R106', 'IV Start Kits / Supplies', '3 kits',
  'compliance', true, false, 'deficiency', false, 106, 80
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=90
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R107', 'EZ-IO Intraosseous Drill & Needles (15mm, 25mm, 40mm)', '1 set',
  'compliance', true, false, 'deficiency', false, 107, 90
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=90
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R108', 'Pressure Infusers (1000cc)', '2',
  'compliance', true, false, 'deficiency', false, 108, 100
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=90
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R109', 'Multi-Channel Smart IV Infusion Pumps', '2 pumps',
  'compliance', true, false, 'deficiency', false, 109, 110
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=90
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R110', 'IV Pump Tubing & Extension Sets', '6 tubing + 6 extension',
  'compliance', true, false, 'deficiency', false, 110, 120
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=90
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R112', 'Albuterol 2.5mg/3mL (Inhalation Solution)', '20 mg (8 doses)',
  'compliance', true, false, 'deficiency', false, 112, 10
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R113', 'Aspirin 81mg Chewable Tablets', '648 mg (8 tabs)',
  'compliance', true, false, 'deficiency', false, 113, 20
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R114', 'Diphenhydramine (Benadryl) 50mg Vial', '50 mg',
  'compliance', true, false, 'deficiency', false, 114, 30
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R115', 'Epinephrine 1mg/mL (1:1,000 Ampules/Vials)', '4 mg (4 amp)',
  'compliance', true, false, 'deficiency', false, 115, 40
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R116', 'Epinephrine 1mg/10mL (1:10,000 Cardiac Preloads)', '9 mg (9 pre)',
  'compliance', true, false, 'deficiency', false, 116, 50
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R117', 'Glucagon 1mg Injectable Kit', '1 mg',
  'compliance', true, false, 'deficiency', false, 117, 60
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R118', 'Oral Glucose Gel (15g Tubes)', '30 g (2 tubes)',
  'compliance', true, false, 'deficiency', false, 118, 70
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R119', 'Ipratropium Bromide (Atrovent) 0.02%', '2.0 mg (4 doses)',
  'compliance', true, false, 'deficiency', false, 119, 80
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R120', 'Naloxone (Narcan) 2mg/2mL Preloads', '8 mg (4 pre)',
  'compliance', true, false, 'deficiency', false, 120, 90
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R121', 'Nitroglycerin SL Tablets (Bottle)', '1 bottle',
  'compliance', true, false, 'deficiency', false, 121, 100
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R122', 'Ondansetron (Zofran) 4mg Oral Dissolve Tabs', '8 mg (2 tabs)',
  'compliance', true, false, 'deficiency', false, 122, 110
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R123', 'Adenosine 6mg Vials', '18 mg (3 vials)',
  'compliance', true, false, 'deficiency', false, 123, 120
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R124', 'Amiodarone 150mg Vials', '450 mg (3 vials)',
  'compliance', true, false, 'deficiency', false, 124, 130
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R125', 'Atropine Sulfate 1mg Preloads', '6 mg (6 pre)',
  'compliance', true, false, 'deficiency', false, 125, 140
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R126', 'Dextrose 10% (D10W) 250mL IV Bags', '50 g (2 bags)',
  'compliance', true, false, 'deficiency', false, 126, 150
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R127', 'Etomidate 20mg Vials', '40 mg (2 vials)',
  'compliance', true, false, 'deficiency', false, 127, 160
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R128', 'Fentanyl 100mcg Vials (Controlled Substance)', '300 mcg (3 vials)',
  'compliance', true, false, 'deficiency', false, 128, 170
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R129', 'Ketamine 500mg Vials (Controlled Substance)', '500 mg (1 vial)',
  'compliance', true, false, 'deficiency', false, 129, 180
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R130', 'Lidocaine 100mg Preloads', '200 mg (2 pre)',
  'compliance', true, false, 'deficiency', false, 130, 190
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R131', 'Magnesium Sulfate 2g IVPB / Vials', '4 g (2 IVPB)',
  'compliance', true, false, 'deficiency', false, 131, 200
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R132', 'Midazolam (Versed) (Controlled Substance)', '30 mg total',
  'compliance', true, false, 'deficiency', false, 132, 210
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R133', 'Norepinephrine (Levophed) 4mg Vials', '4 mg (1 vial)',
  'compliance', true, false, 'deficiency', false, 133, 220
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R134', 'Sodium Bicarbonate 8.4% 50mEq Preloads', '100 mEq (2 pre)',
  'compliance', true, false, 'deficiency', false, 134, 230
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R135', 'Tranexamic Acid (TXA) 1g Vials', '1 g (1 vial)',
  'compliance', true, false, 'deficiency', false, 135, 240
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R136', 'Verapamil 5mg Vials', '10 mg (2 vials)',
  'compliance', true, false, 'deficiency', false, 136, 250
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R137', 'Zofran 4mg/2mL IV Vials', '8 mg (2 vials)',
  'compliance', true, false, 'deficiency', false, 137, 260
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R138', 'Tetracaine 0.5% Ophthalmic Eye Drops', '1 bottle',
  'compliance', true, false, 'deficiency', false, 138, 270
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R139', 'Labetalol 100mg/20mL Vial (CCT)', '100 mg (1 vial)',
  'compliance', true, false, 'deficiency', false, 139, 280
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R140', 'Metoprolol (Lopressor) 5mg Vials (CCT)', '15 mg (3 vials)',
  'compliance', true, false, 'deficiency', false, 140, 290
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R141', 'Metoclopramide (Reglan) 10mg Vial (CCT)', '10 mg (1 vial)',
  'compliance', true, false, 'deficiency', false, 141, 300
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R142', 'Propofol (Diprivan) 1000mg/100mL (Controlled - CCT)', '1000 mg (1 btl)',
  'compliance', true, false, 'deficiency', false, 142, 310
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R143', 'Vecuronium (Norcuron) 10mg w/ Bacteriostatic H2O (CCT)', '10 mg (1 set)',
  'compliance', true, false, 'deficiency', false, 143, 320
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=100
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R145', 'Broselow Length-Based Assessment Tape', '1',
  'compliance', true, false, 'deficiency', false, 145, 10
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=110
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R146', 'Pediatric Trauma Score Reference', '1',
  'compliance', true, false, 'deficiency', false, 146, 20
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=110
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R147', 'Silver Swaddler & Newborn Head Cover', '1 each',
  'compliance', true, false, 'deficiency', false, 147, 30
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=110
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R148', 'Sterile Obstetrical Kit w/ Bulb Syringe', '1 kit',
  'compliance', true, false, 'deficiency', false, 148, 40
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=110
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R149', 'Disaster Triage Tags (SMART Tags - 20 w/ START/JumpSTART)', '1 kit (20)',
  'compliance', true, false, 'deficiency', false, 149, 50
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=110
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R150', 'Ambulance Patient Care Run Report Backups (Paper)', '10',
  'compliance', true, false, 'deficiency', false, 150, 60
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=110
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R151', 'GEA Standing Medical Orders (SMO Printed Copy)', '1',
  'compliance', true, false, 'deficiency', false, 151, 70
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=110
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R152', 'Blankets (Mylar or Cloth)', '2',
  'compliance', true, false, 'deficiency', false, 152, 80
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=110
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R153', 'Sheets & Towels', '2 sheets, 2 towels',
  'compliance', true, false, 'deficiency', false, 153, 90
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=110
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R154', 'Urinal & Bedpan', '1 each',
  'compliance', true, false, 'deficiency', false, 154, 100
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=110
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R155', 'Cold Packs / Thermal Packs', '8 cold / 3 warm',
  'compliance', true, false, 'deficiency', false, 155, 110
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=110
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R156', 'PPE (Gloves, Gowns, Masks, Eye Protection, Biohazard Bags)', 'Required',
  'compliance', true, false, 'deficiency', false, 156, 120
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=110
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R157', 'ANSI Reflective Vests', '1 / provider',
  'compliance', true, false, 'deficiency', false, 157, 130
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=110
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R158', 'Sharps Container & Ampule Breaker', '1 sharps, 2 amp',
  'compliance', true, false, 'deficiency', false, 158, 140
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=110
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;

insert into public.inspection_form_items(
  section_id, item_code, label, requirement_text, response_type, required,
  allow_na, failure_severity, requires_comment_on_fail, source_row, sort_order
)
select s.id, 'MATRIX_R159', 'Chemical Disinfectants (Hand Cleanser & Surface Cleaner)', '1 each',
  'compliance', true, false, 'deficiency', false, 159, 150
from public.inspection_form_sections s
join public.inspection_form_versions v on v.id=s.form_version_id
join public.inspection_form_templates t on t.id=v.template_id
where t.code='GEA_CC_TRANSPORT_EQUIPMENT' and v.version_number=1 and s.sort_order=110
on conflict (section_id, item_code) do update
set label=excluded.label, requirement_text=excluded.requirement_text,
    response_type=excluded.response_type, required=excluded.required,
    allow_na=excluded.allow_na, source_row=excluded.source_row, sort_order=excluded.sort_order;


-- -----------------------------------------------------------------------------
-- Atomic save/submit RPC for the digital inspection workflow.
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

  -- Replace the current draft responses with the payload supplied by the form.
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
    and (r.status is not null or nullif(btrim(r.observed_value),'') is not null or nullif(btrim(r.notes),'') is not null);

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
      and r.status in ('pass','fail','na')
      and (r.status <> 'na' or i.allow_na = true);

    if v_answered_count <> v_required_count then
      raise exception 'Every required inspection item must be marked compliant or deficient before submission';
    end if;

    if exists (
      select 1
      from public.inspection_item_responses r
      join public.inspection_form_items i on i.id = r.form_item_id
      where r.vehicle_inspection_id = v_inspection_id
        and r.status = 'fail'
        and i.requires_comment_on_fail = true
        and coalesce(btrim(r.notes),'') = ''
    ) then
      raise exception 'A comment is required for one or more deficient items';
    end if;

    select count(*) into v_fail_count
    from public.inspection_item_responses
    where vehicle_inspection_id = v_inspection_id and status = 'fail';

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
