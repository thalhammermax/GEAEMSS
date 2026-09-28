-- GEAEMS Portal v0.2
-- Configurable built-in fields + custom fields for providers, agencies, and vehicles.
-- Also expands provider record updates to agency administrators who have personnel-management permission.
-- Run AFTER 001_initial_schema.sql.

begin;

-- -----------------------------------------------------------------------------
-- Provider record management helper
-- -----------------------------------------------------------------------------

create or replace function private.can_manage_provider_record(p_provider_id uuid)
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
        and uaa.can_manage_personnel = true
    );
$$;

revoke execute on function private.can_manage_provider_record(uuid) from public, anon;
grant execute on function private.can_manage_provider_record(uuid) to authenticated;

-- Replace the system-admin-only provider UPDATE policy with a permission-aware policy.
drop policy if exists providers_system_admin_update on public.providers;
create policy providers_manage_update on public.providers
for update to authenticated
using ((select private.can_manage_provider_record(id)))
with check ((select private.can_manage_provider_record(id)));

-- -----------------------------------------------------------------------------
-- Atomic provider creation for System/Agency Administrators
-- -----------------------------------------------------------------------------

create or replace function public.create_provider_with_primary_agency(
  p_agency_id uuid,
  p_provider jsonb,
  p_affiliation jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_provider_id uuid;
  v_first_name text := nullif(btrim(p_provider ->> 'first_name'), '');
  v_last_name text := nullif(btrim(p_provider ->> 'last_name'), '');
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required';
  end if;

  if not private.can_manage_agency_personnel(p_agency_id) then
    raise exception 'You do not have permission to add personnel to this agency';
  end if;

  if v_first_name is null or v_last_name is null then
    raise exception 'First name and last name are required';
  end if;

  insert into public.providers (
    first_name,
    middle_name,
    last_name,
    preferred_name,
    provider_number,
    provider_level_id,
    provider_status_id,
    system_entry_date,
    email,
    phone,
    notes
  ) values (
    v_first_name,
    nullif(btrim(p_provider ->> 'middle_name'), ''),
    v_last_name,
    nullif(btrim(p_provider ->> 'preferred_name'), ''),
    nullif(btrim(p_provider ->> 'provider_number'), ''),
    nullif(p_provider ->> 'provider_level_id', '')::uuid,
    nullif(p_provider ->> 'provider_status_id', '')::uuid,
    nullif(p_provider ->> 'system_entry_date', '')::date,
    nullif(btrim(p_provider ->> 'email'), ''),
    nullif(btrim(p_provider ->> 'phone'), ''),
    nullif(btrim(p_provider ->> 'notes'), '')
  ) returning id into v_provider_id;

  insert into public.provider_agencies (
    provider_id,
    agency_id,
    employee_id,
    agency_provider_level_id,
    start_date,
    is_primary,
    active
  ) values (
    v_provider_id,
    p_agency_id,
    nullif(btrim(p_affiliation ->> 'employee_id'), ''),
    nullif(p_affiliation ->> 'agency_provider_level_id', '')::uuid,
    nullif(p_affiliation ->> 'start_date', '')::date,
    true,
    true
  );

  return v_provider_id;
end;
$$;

revoke all on function public.create_provider_with_primary_agency(uuid, jsonb, jsonb) from public, anon;
grant execute on function public.create_provider_with_primary_agency(uuid, jsonb, jsonb) to authenticated;

-- -----------------------------------------------------------------------------
-- Field definitions
-- -----------------------------------------------------------------------------

create table if not exists public.record_field_definitions (
  id uuid primary key default gen_random_uuid(),
  entity_type text not null check (entity_type in ('provider', 'agency', 'vehicle')),
  field_key text not null,
  label text not null,
  field_type text not null check (
    field_type in ('text', 'textarea', 'number', 'date', 'boolean', 'email', 'phone', 'url', 'select', 'multiselect')
  ),
  source_type text not null default 'custom' check (source_type in ('builtin', 'custom')),
  builtin_column text,
  field_group text not null default 'Additional Information',
  help_text text,
  placeholder text,
  options jsonb not null default '[]'::jsonb,
  enabled boolean not null default true,
  required boolean not null default false,
  system_locked boolean not null default false,
  sort_order integer not null default 100,
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint record_field_definitions_key_unique unique(entity_type, field_key),
  constraint record_field_builtin_check check (
    (source_type = 'builtin' and builtin_column is not null)
    or (source_type = 'custom' and builtin_column is null)
  ),
  constraint record_field_options_array check (jsonb_typeof(options) = 'array')
);

create index if not exists record_field_definitions_entity_idx
  on public.record_field_definitions(entity_type, enabled, sort_order);

-- Custom values are intentionally polymorphic. A trigger validates that the
-- entity exists in the correct underlying table before a value can be written.
create table if not exists public.record_custom_field_values (
  id uuid primary key default gen_random_uuid(),
  field_definition_id uuid not null references public.record_field_definitions(id) on delete cascade,
  entity_id uuid not null,
  value jsonb not null,
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  updated_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(field_definition_id, entity_id)
);

create index if not exists record_custom_field_values_entity_idx
  on public.record_custom_field_values(entity_id);
create index if not exists record_custom_field_values_field_idx
  on public.record_custom_field_values(field_definition_id);

-- -----------------------------------------------------------------------------
-- Validation and authorization helpers
-- -----------------------------------------------------------------------------

create or replace function private.record_entity_exists(p_entity_type text, p_entity_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case p_entity_type
    when 'provider' then exists (select 1 from public.providers p where p.id = p_entity_id)
    when 'agency' then exists (select 1 from public.agencies a where a.id = p_entity_id)
    when 'vehicle' then exists (select 1 from public.vehicles v where v.id = p_entity_id)
    else false
  end;
$$;

create or replace function private.can_view_record_entity(p_entity_type text, p_entity_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case p_entity_type
    when 'provider' then private.can_view_provider(p_entity_id)
    when 'agency' then (
      private.is_system_admin()
      or private.has_agency_access(p_entity_id)
      or exists (
        select 1
        from public.provider_agencies pa
        where pa.agency_id = p_entity_id
          and pa.provider_id = private.my_provider_id()
          and pa.active = true
      )
    )
    when 'vehicle' then private.can_view_vehicle(p_entity_id)
    else false
  end;
$$;

create or replace function private.can_manage_record_entity(p_entity_type text, p_entity_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case p_entity_type
    when 'provider' then private.can_manage_provider_record(p_entity_id)
    when 'agency' then private.is_system_admin()
    when 'vehicle' then private.can_manage_vehicle(p_entity_id)
    else false
  end;
$$;

revoke execute on function private.record_entity_exists(text, uuid) from public, anon;
revoke execute on function private.can_view_record_entity(text, uuid) from public, anon;
revoke execute on function private.can_manage_record_entity(text, uuid) from public, anon;
grant execute on function private.record_entity_exists(text, uuid) to authenticated;
grant execute on function private.can_view_record_entity(text, uuid) to authenticated;
grant execute on function private.can_manage_record_entity(text, uuid) to authenticated;

create or replace function private.validate_record_custom_field_value()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_def public.record_field_definitions%rowtype;
  v_type text;
begin
  select * into v_def
  from public.record_field_definitions
  where id = new.field_definition_id;

  if not found then
    raise exception 'Field definition not found';
  end if;

  if v_def.source_type <> 'custom' then
    raise exception 'Values can only be stored for custom fields';
  end if;

  if not private.record_entity_exists(v_def.entity_type, new.entity_id) then
    raise exception 'The % record does not exist', v_def.entity_type;
  end if;

  v_type := jsonb_typeof(new.value);

  if v_def.field_type in ('text', 'textarea', 'date', 'email', 'phone', 'url', 'select') and v_type <> 'string' then
    raise exception 'Field % expects a text value', v_def.label;
  elsif v_def.field_type = 'number' and v_type <> 'number' then
    raise exception 'Field % expects a numeric value', v_def.label;
  elsif v_def.field_type = 'boolean' and v_type <> 'boolean' then
    raise exception 'Field % expects a true/false value', v_def.label;
  elsif v_def.field_type = 'multiselect' and v_type <> 'array' then
    raise exception 'Field % expects a list value', v_def.label;
  end if;

  new.updated_by := auth.uid();
  new.updated_at := now();
  return new;
end;
$$;

revoke execute on function private.validate_record_custom_field_value() from public, anon, authenticated;

drop trigger if exists validate_record_custom_field_value on public.record_custom_field_values;
create trigger validate_record_custom_field_value
before insert or update on public.record_custom_field_values
for each row execute function private.validate_record_custom_field_value();

create trigger set_record_field_definitions_updated_at
before update on public.record_field_definitions
for each row execute function private.set_updated_at();

-- Keep generic custom values from becoming orphaned if an administrator ever
-- permanently deletes a parent record. Normal application behavior is archive/inactivate.
create or replace function private.cleanup_record_custom_field_values()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.record_custom_field_values v
  using public.record_field_definitions f
  where v.field_definition_id = f.id
    and v.entity_id = old.id
    and f.entity_type = tg_argv[0];
  return old;
end;
$$;

revoke execute on function private.cleanup_record_custom_field_values() from public, anon, authenticated;

create trigger cleanup_provider_custom_field_values
after delete on public.providers
for each row execute function private.cleanup_record_custom_field_values('provider');

create trigger cleanup_agency_custom_field_values
after delete on public.agencies
for each row execute function private.cleanup_record_custom_field_values('agency');

create trigger cleanup_vehicle_custom_field_values
after delete on public.vehicles
for each row execute function private.cleanup_record_custom_field_values('vehicle');

-- Audit both configuration changes and custom-value changes.
create trigger audit_record_field_definitions
after insert or update or delete on public.record_field_definitions
for each row execute function private.audit_row_change();

create trigger audit_record_custom_field_values
after insert or update or delete on public.record_custom_field_values
for each row execute function private.audit_row_change();

-- -----------------------------------------------------------------------------
-- RLS
-- -----------------------------------------------------------------------------

alter table public.record_field_definitions enable row level security;
alter table public.record_custom_field_values enable row level security;

grant select on public.record_field_definitions to authenticated;
grant insert, update, delete on public.record_field_definitions to authenticated;
grant select, insert, update, delete on public.record_custom_field_values to authenticated;

create policy record_field_definitions_read on public.record_field_definitions
for select to authenticated using (true);

create policy record_field_definitions_admin_write on public.record_field_definitions
for all to authenticated
using ((select private.is_system_admin()))
with check ((select private.is_system_admin()));

create policy record_custom_field_values_read on public.record_custom_field_values
for select to authenticated
using (
  exists (
    select 1
    from public.record_field_definitions f
    where f.id = field_definition_id
      and private.can_view_record_entity(f.entity_type, entity_id)
  )
);

create policy record_custom_field_values_insert on public.record_custom_field_values
for insert to authenticated
with check (
  exists (
    select 1
    from public.record_field_definitions f
    where f.id = field_definition_id
      and f.source_type = 'custom'
      and private.can_manage_record_entity(f.entity_type, entity_id)
  )
);

create policy record_custom_field_values_update on public.record_custom_field_values
for update to authenticated
using (
  exists (
    select 1
    from public.record_field_definitions f
    where f.id = field_definition_id
      and private.can_manage_record_entity(f.entity_type, entity_id)
  )
)
with check (
  exists (
    select 1
    from public.record_field_definitions f
    where f.id = field_definition_id
      and f.source_type = 'custom'
      and private.can_manage_record_entity(f.entity_type, entity_id)
  )
);

create policy record_custom_field_values_delete on public.record_custom_field_values
for delete to authenticated
using (
  exists (
    select 1
    from public.record_field_definitions f
    where f.id = field_definition_id
      and private.can_manage_record_entity(f.entity_type, entity_id)
  )
);

-- -----------------------------------------------------------------------------
-- Seed configurable built-in fields
-- Core identity fields are system_locked so they remain enabled/required.
-- -----------------------------------------------------------------------------

insert into public.record_field_definitions
  (entity_type, field_key, label, field_type, source_type, builtin_column, field_group, enabled, required, system_locked, sort_order)
values
  ('provider','first_name','First name','text','builtin','first_name','Identity',true,true,true,10),
  ('provider','middle_name','Middle name','text','builtin','middle_name','Identity',true,false,false,20),
  ('provider','last_name','Last name','text','builtin','last_name','Identity',true,true,true,30),
  ('provider','preferred_name','Preferred name','text','builtin','preferred_name','Identity',true,false,false,40),
  ('provider','provider_number','System provider ID','text','builtin','provider_number','System Information',true,false,false,50),
  ('provider','system_entry_date','System entry date','date','builtin','system_entry_date','System Information',true,false,false,60),
  ('provider','provider_level_id','Provider level','select','builtin','provider_level_id','System Information',true,false,false,70),
  ('provider','provider_status_id','System status','select','builtin','provider_status_id','System Information',true,false,false,80),
  ('provider','email','Email','email','builtin','email','Contact',true,false,false,90),
  ('provider','phone','Phone','phone','builtin','phone','Contact',true,false,false,100),
  ('provider','notes','Notes','textarea','builtin','notes','Additional Information',true,false,false,110),

  ('agency','name','Agency name','text','builtin','name','Agency',true,true,true,10),
  ('agency','short_name','Abbreviation','text','builtin','short_name','Agency',true,false,false,20),

  ('vehicle','agency_id','Agency','select','builtin','agency_id','Assignment',true,true,true,10),
  ('vehicle','unit_number','Unit number','text','builtin','unit_number','Identification',true,false,false,20),
  ('vehicle','fleet_number','Fleet number','text','builtin','fleet_number','Identification',true,false,false,30),
  ('vehicle','vehicle_type_id','Vehicle type','select','builtin','vehicle_type_id','Classification',true,false,false,40),
  ('vehicle','vehicle_status_id','Vehicle status','select','builtin','vehicle_status_id','Classification',true,false,false,50),
  ('vehicle','vin','VIN','text','builtin','vin','Identification',true,false,false,60),
  ('vehicle','year','Year','number','builtin','year','Vehicle',true,false,false,70),
  ('vehicle','make','Make','text','builtin','make','Vehicle',true,false,false,80),
  ('vehicle','model','Model','text','builtin','model','Vehicle',true,false,false,90),
  ('vehicle','license_plate','License plate','text','builtin','license_plate','Registration',true,false,false,100),
  ('vehicle','license_plate_state','Plate state','text','builtin','license_plate_state','Registration',true,false,false,110),
  ('vehicle','in_service_date','In-service date','date','builtin','in_service_date','Service',true,false,false,120),
  ('vehicle','retired_date','Retired date','date','builtin','retired_date','Service',true,false,false,130),
  ('vehicle','notes','Notes','textarea','builtin','notes','Additional Information',true,false,false,140)
on conflict (entity_type, field_key) do nothing;

commit;
