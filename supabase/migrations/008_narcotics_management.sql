-- GEAEMS Portal v0.6
-- Narcotics Management: daily ALS apparatus counts, electronic signatures,
-- agency-scoped provider access, configurable count templates, and daily
-- incomplete-count reporting support.
-- Run after migrations 001 through 007.

begin;

-- -----------------------------------------------------------------------------
-- Agency permissions and fleet configuration
-- -----------------------------------------------------------------------------

alter table public.user_agency_access
  add column if not exists can_manage_narcotics boolean not null default false,
  add column if not exists receive_narcotics_reports boolean not null default true;

-- -----------------------------------------------------------------------------
-- Narcotics inventory templates and agency settings
-- -----------------------------------------------------------------------------

create table if not exists public.narcotics_count_templates (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text,
  scope_type text not null default 'system' check (scope_type in ('system','agency')),
  agency_id uuid references public.agencies(id) on delete cascade,
  active boolean not null default true,
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint narcotics_count_templates_scope_check check (
    (scope_type = 'system' and agency_id is null)
    or
    (scope_type = 'agency' and agency_id is not null)
  )
);

create unique index if not exists narcotics_count_templates_system_name_unique
  on public.narcotics_count_templates(lower(name))
  where scope_type = 'system' and active = true;

create unique index if not exists narcotics_count_templates_agency_name_unique
  on public.narcotics_count_templates(agency_id, lower(name))
  where scope_type = 'agency' and active = true;

create index if not exists narcotics_count_templates_agency_idx
  on public.narcotics_count_templates(agency_id);

create table if not exists public.narcotics_count_template_items (
  id uuid primary key default gen_random_uuid(),
  template_id uuid not null references public.narcotics_count_templates(id) on delete cascade,
  medication_name text not null,
  concentration text,
  dosage_form text,
  controlled_substance_schedule text,
  unit_label text not null default 'unit',
  expected_quantity numeric(10,3) not null default 0 check (expected_quantity >= 0),
  sort_order integer not null default 100,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists narcotics_count_template_items_template_idx
  on public.narcotics_count_template_items(template_id, sort_order, medication_name);

create table if not exists public.narcotics_agency_settings (
  agency_id uuid primary key references public.agencies(id) on delete cascade,
  enabled boolean not null default true,
  timezone text not null default 'America/Chicago',
  report_hour smallint not null default 8 check (report_hour between 0 and 23),
  send_incomplete_report boolean not null default true,
  default_template_id uuid references public.narcotics_count_templates(id) on delete set null,
  signature_attestation text not null default 'I attest that I personally performed this narcotics inventory count and that the quantities entered are accurate to the best of my knowledge.',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Vehicles can use the agency default template or override it per apparatus.
alter table public.vehicles
  add column if not exists narcotics_count_required boolean not null default false,
  add column if not exists narcotics_template_id uuid references public.narcotics_count_templates(id) on delete set null;

create or replace function private.enforce_als_narcotics_requirement()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if exists (
    select 1 from public.vehicle_types vt
    where vt.id = new.vehicle_type_id
      and vt.code in ('GEA_ALS_NON_TRANSPORT','GEA_ALS_AMBULANCE','GEA_CC_TRANSPORT')
  ) then
    new.narcotics_count_required := true;
  end if;
  return new;
end;
$$;

revoke execute on function private.enforce_als_narcotics_requirement() from public, anon, authenticated;

drop trigger if exists enforce_als_narcotics_requirement on public.vehicles;
create trigger enforce_als_narcotics_requirement
before insert or update of vehicle_type_id, narcotics_count_required on public.vehicles
for each row execute function private.enforce_als_narcotics_requirement();

-- Existing ALS / critical-care apparatus from the inspection matrix are daily-count units by default.
update public.vehicles v
set narcotics_count_required = true
from public.vehicle_types vt
where v.vehicle_type_id = vt.id
  and vt.code in ('GEA_ALS_NON_TRANSPORT','GEA_ALS_AMBULANCE','GEA_CC_TRANSPORT');

-- Create settings rows for all active agencies so reporting can be configured immediately.
insert into public.narcotics_agency_settings(agency_id)
select id from public.agencies
on conflict (agency_id) do nothing;

-- -----------------------------------------------------------------------------
-- Daily count records and electronic signatures
-- -----------------------------------------------------------------------------

create table if not exists public.narcotics_counts (
  id uuid primary key default gen_random_uuid(),
  agency_id uuid not null references public.agencies(id) on delete restrict,
  vehicle_id uuid not null references public.vehicles(id) on delete restrict,
  template_id uuid not null references public.narcotics_count_templates(id) on delete restrict,
  count_date date not null,
  status text not null default 'draft' check (status in ('draft','submitted','void')),
  started_by uuid references auth.users(id) on delete set null default auth.uid(),
  started_provider_id uuid references public.providers(id) on delete set null,
  started_at timestamptz not null default now(),
  submitted_by uuid references auth.users(id) on delete set null,
  submitted_provider_id uuid references public.providers(id) on delete set null,
  signed_name text,
  signature_attestation text,
  signed_at timestamptz,
  signature_hash text,
  has_discrepancy boolean not null default false,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(vehicle_id, count_date),
  constraint narcotics_counts_signature_check check (
    (status = 'submitted' and submitted_by is not null and submitted_provider_id is not null and signed_name is not null and signed_at is not null and signature_hash is not null)
    or status <> 'submitted'
  )
);

create index if not exists narcotics_counts_agency_date_idx
  on public.narcotics_counts(agency_id, count_date desc);
create index if not exists narcotics_counts_vehicle_date_idx
  on public.narcotics_counts(vehicle_id, count_date desc);
create index if not exists narcotics_counts_status_idx
  on public.narcotics_counts(status, count_date desc);

create table if not exists public.narcotics_count_lines (
  id uuid primary key default gen_random_uuid(),
  count_id uuid not null references public.narcotics_counts(id) on delete cascade,
  template_item_id uuid references public.narcotics_count_template_items(id) on delete set null,
  medication_name text not null,
  concentration text,
  dosage_form text,
  unit_label text not null,
  expected_quantity numeric(10,3) not null check (expected_quantity >= 0),
  actual_quantity numeric(10,3) check (actual_quantity is null or actual_quantity >= 0),
  discrepancy boolean generated always as (
    actual_quantity is not null and actual_quantity <> expected_quantity
  ) stored,
  notes text,
  sort_order integer not null default 100,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(count_id, template_item_id)
);

create index if not exists narcotics_count_lines_count_idx
  on public.narcotics_count_lines(count_id, sort_order);
create index if not exists narcotics_count_lines_discrepancy_idx
  on public.narcotics_count_lines(count_id)
  where discrepancy = true;

create table if not exists public.narcotics_report_history (
  id bigint generated always as identity primary key,
  agency_id uuid not null references public.agencies(id) on delete cascade,
  report_date date not null,
  report_type text not null default 'incomplete_daily_count' check (report_type = 'incomplete_daily_count'),
  status text not null default 'sent' check (status in ('sent','skipped','failed')),
  missing_vehicle_ids uuid[] not null default '{}',
  recipients jsonb not null default '[]'::jsonb,
  provider_message_id text,
  error_message text,
  created_at timestamptz not null default now(),
  unique(agency_id, report_date, report_type)
);

create index if not exists narcotics_report_history_agency_idx
  on public.narcotics_report_history(agency_id, report_date desc);

-- -----------------------------------------------------------------------------
-- Authorization helpers
-- -----------------------------------------------------------------------------

create or replace function private.is_provider_member_of_agency(p_agency_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.is_user_active()
    and exists (
      select 1
      from public.provider_agencies pa
      where pa.provider_id = private.my_provider_id()
        and pa.agency_id = p_agency_id
        and pa.active = true
        and (pa.start_date is null or pa.start_date <= current_date)
        and (pa.end_date is null or pa.end_date >= current_date)
    );
$$;

create or replace function private.can_view_narcotics_agency(p_agency_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.is_user_active()
    and (
      private.is_system_admin()
      or private.has_agency_access(p_agency_id)
      or private.is_provider_member_of_agency(p_agency_id)
    );
$$;

create or replace function private.can_manage_agency_narcotics(p_agency_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.is_user_active()
    and (
      private.is_system_admin()
      or (
        private.is_agency_admin()
        and exists (
          select 1
          from public.user_agency_access uaa
          where uaa.user_id = (select auth.uid())
            and uaa.agency_id = p_agency_id
            and uaa.can_manage_narcotics = true
        )
      )
    );
$$;

create or replace function private.can_view_narcotics_template(p_template_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.is_user_active()
    and exists (
      select 1
      from public.narcotics_count_templates t
      where t.id = p_template_id
        and (
          private.is_system_admin()
          or t.scope_type = 'system'
          or (t.scope_type = 'agency' and private.can_view_narcotics_agency(t.agency_id))
        )
    );
$$;

create or replace function private.can_manage_narcotics_template(p_template_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.is_user_active()
    and exists (
      select 1
      from public.narcotics_count_templates t
      where t.id = p_template_id
        and (
          (t.scope_type = 'system' and private.is_system_admin())
          or (t.scope_type = 'agency' and private.can_manage_agency_narcotics(t.agency_id))
        )
    );
$$;

create or replace function private.can_view_narcotics_count(p_count_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.is_user_active()
    and exists (
      select 1
      from public.narcotics_counts c
      where c.id = p_count_id
        and private.can_view_narcotics_agency(c.agency_id)
    );
$$;

revoke execute on function private.is_provider_member_of_agency(uuid) from public, anon;
revoke execute on function private.can_view_narcotics_agency(uuid) from public, anon;
revoke execute on function private.can_manage_agency_narcotics(uuid) from public, anon;
revoke execute on function private.can_view_narcotics_template(uuid) from public, anon;
revoke execute on function private.can_manage_narcotics_template(uuid) from public, anon;
revoke execute on function private.can_view_narcotics_count(uuid) from public, anon;

grant execute on function private.is_provider_member_of_agency(uuid) to authenticated;
grant execute on function private.can_view_narcotics_agency(uuid) to authenticated;
grant execute on function private.can_manage_agency_narcotics(uuid) to authenticated;
grant execute on function private.can_view_narcotics_template(uuid) to authenticated;
grant execute on function private.can_manage_narcotics_template(uuid) to authenticated;
grant execute on function private.can_view_narcotics_count(uuid) to authenticated;

-- Providers need read-only access to narcotics-count apparatus in agencies where
-- they are active members. This does not grant general Fleet management.
drop policy if exists vehicles_read on public.vehicles;
create policy vehicles_read on public.vehicles
for select to authenticated
using (
  (select private.is_system_inspector())
  or (select private.has_agency_access(agency_id))
  or (narcotics_count_required = true and (select private.is_provider_member_of_agency(agency_id)))
);

-- -----------------------------------------------------------------------------
-- RLS
-- -----------------------------------------------------------------------------

alter table public.narcotics_count_templates enable row level security;
alter table public.narcotics_count_template_items enable row level security;
alter table public.narcotics_agency_settings enable row level security;
alter table public.narcotics_counts enable row level security;
alter table public.narcotics_count_lines enable row level security;
alter table public.narcotics_report_history enable row level security;

grant select, insert, update, delete on
  public.narcotics_count_templates,
  public.narcotics_count_template_items,
  public.narcotics_agency_settings
to authenticated;

grant select on
  public.narcotics_counts,
  public.narcotics_count_lines,
  public.narcotics_report_history
to authenticated;

-- Template definitions
drop policy if exists narcotics_count_templates_read on public.narcotics_count_templates;
create policy narcotics_count_templates_read on public.narcotics_count_templates
for select to authenticated
using (
  scope_type = 'system'
  or (scope_type = 'agency' and (select private.can_view_narcotics_agency(agency_id)))
  or (select private.is_system_admin())
);

create policy narcotics_count_templates_insert on public.narcotics_count_templates
for insert to authenticated
with check (
  (scope_type = 'system' and (select private.is_system_admin()))
  or (scope_type = 'agency' and agency_id is not null and (select private.can_manage_agency_narcotics(agency_id)))
);

create policy narcotics_count_templates_update on public.narcotics_count_templates
for update to authenticated
using ((select private.can_manage_narcotics_template(id)))
with check (
  (scope_type = 'system' and (select private.is_system_admin()))
  or (scope_type = 'agency' and agency_id is not null and (select private.can_manage_agency_narcotics(agency_id)))
);

create policy narcotics_count_templates_delete on public.narcotics_count_templates
for delete to authenticated
using ((select private.can_manage_narcotics_template(id)));

-- Template line items
create policy narcotics_count_template_items_read on public.narcotics_count_template_items
for select to authenticated
using ((select private.can_view_narcotics_template(template_id)));

create policy narcotics_count_template_items_insert on public.narcotics_count_template_items
for insert to authenticated
with check ((select private.can_manage_narcotics_template(template_id)));

create policy narcotics_count_template_items_update on public.narcotics_count_template_items
for update to authenticated
using ((select private.can_manage_narcotics_template(template_id)))
with check ((select private.can_manage_narcotics_template(template_id)));

create policy narcotics_count_template_items_delete on public.narcotics_count_template_items
for delete to authenticated
using ((select private.can_manage_narcotics_template(template_id)));

-- Agency settings
create policy narcotics_agency_settings_read on public.narcotics_agency_settings
for select to authenticated
using ((select private.can_view_narcotics_agency(agency_id)));

create policy narcotics_agency_settings_insert on public.narcotics_agency_settings
for insert to authenticated
with check ((select private.can_manage_agency_narcotics(agency_id)));

create policy narcotics_agency_settings_update on public.narcotics_agency_settings
for update to authenticated
using ((select private.can_manage_agency_narcotics(agency_id)))
with check ((select private.can_manage_agency_narcotics(agency_id)));

create policy narcotics_agency_settings_delete on public.narcotics_agency_settings
for delete to authenticated
using ((select private.is_system_admin()));

-- Submitted/draft count records are written only through the RPC below.
create policy narcotics_counts_read on public.narcotics_counts
for select to authenticated
using ((select private.can_view_narcotics_agency(agency_id)));

create policy narcotics_count_lines_read on public.narcotics_count_lines
for select to authenticated
using ((select private.can_view_narcotics_count(count_id)));

create policy narcotics_report_history_read on public.narcotics_report_history
for select to authenticated
using (
  (select private.is_system_admin())
  or (select private.can_manage_agency_narcotics(agency_id))
);

-- -----------------------------------------------------------------------------
-- Save/sign RPC. Providers must be linked to the agency they are counting for.
-- System/Agency administrative status alone does not authorize a signature.
-- -----------------------------------------------------------------------------

create or replace function public.save_narcotics_count(
  p_count_id uuid,
  p_vehicle_id uuid,
  p_count_date date,
  p_notes text,
  p_mode text,
  p_signature_name text,
  p_attestation boolean,
  p_lines jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_provider_id uuid;
  v_agency_id uuid;
  v_template_id uuid;
  v_count_id uuid;
  v_status text;
  v_attestation text;
  v_expected_count integer;
  v_entered_count integer;
  v_signed_at timestamptz;
  v_signature_payload text;
begin
  if v_user_id is null or not private.is_user_active() then
    raise exception 'An active portal login is required.';
  end if;

  select provider_id into v_provider_id
  from public.profiles
  where id = v_user_id and active = true;

  if v_provider_id is null then
    raise exception 'Your portal account is not linked to a provider record.';
  end if;

  select v.agency_id,
         coalesce(v.narcotics_template_id, s.default_template_id)
    into v_agency_id, v_template_id
  from public.vehicles v
  left join public.narcotics_agency_settings s on s.agency_id = v.agency_id
  where v.id = p_vehicle_id
    and v.active = true
    and v.narcotics_count_required = true;

  if v_agency_id is null then
    raise exception 'This vehicle is not configured for daily narcotics counts.';
  end if;

  if not exists (
    select 1
    from public.provider_agencies pa
    where pa.provider_id = v_provider_id
      and pa.agency_id = v_agency_id
      and pa.active = true
      and (pa.start_date is null or pa.start_date <= p_count_date)
      and (pa.end_date is null or pa.end_date >= p_count_date)
  ) then
    raise exception 'You may only perform narcotics counts for agencies where you are an active provider.';
  end if;

  if v_template_id is null then
    raise exception 'No narcotics count template is assigned to this vehicle or its agency.';
  end if;

  if not exists (
    select 1
    from public.narcotics_count_templates t
    where t.id = v_template_id
      and t.active = true
      and (t.scope_type = 'system' or t.agency_id = v_agency_id)
  ) then
    raise exception 'The assigned narcotics count template is not available for this agency.';
  end if;

  if p_mode not in ('draft','submit') then
    raise exception 'Invalid save mode.';
  end if;

  if p_count_id is not null then
    select id, status into v_count_id, v_status
    from public.narcotics_counts
    where id = p_count_id
      and vehicle_id = p_vehicle_id
      and count_date = p_count_date
    for update;

    if v_count_id is null then
      raise exception 'Narcotics count record not found.';
    end if;
    if v_status <> 'draft' then
      raise exception 'A submitted narcotics count cannot be edited.';
    end if;
  else
    select id, status into v_count_id, v_status
    from public.narcotics_counts
    where vehicle_id = p_vehicle_id
      and count_date = p_count_date
    for update;

    if v_count_id is not null and v_status <> 'draft' then
      raise exception 'This apparatus already has a submitted narcotics count for that date.';
    end if;

    if v_count_id is null then
      insert into public.narcotics_counts(
        agency_id, vehicle_id, template_id, count_date,
        status, started_by, started_provider_id, notes
      ) values (
        v_agency_id, p_vehicle_id, v_template_id, p_count_date,
        'draft', v_user_id, v_provider_id, nullif(btrim(p_notes), '')
      ) returning id into v_count_id;
    end if;
  end if;

  update public.narcotics_counts
  set notes = nullif(btrim(p_notes), ''),
      template_id = v_template_id,
      updated_at = now()
  where id = v_count_id;

  delete from public.narcotics_count_lines where count_id = v_count_id;

  insert into public.narcotics_count_lines(
    count_id, template_item_id, medication_name, concentration, dosage_form,
    unit_label, expected_quantity, actual_quantity, notes, sort_order
  )
  select
    v_count_id,
    ti.id,
    ti.medication_name,
    ti.concentration,
    ti.dosage_form,
    ti.unit_label,
    ti.expected_quantity,
    nullif(line.value->>'actual_quantity','')::numeric,
    nullif(btrim(line.value->>'notes'), ''),
    ti.sort_order
  from jsonb_array_elements(coalesce(p_lines, '[]'::jsonb)) as line(value)
  join public.narcotics_count_template_items ti
    on ti.id = (line.value->>'item_id')::uuid
   and ti.template_id = v_template_id
   and ti.active = true;

  if p_mode = 'submit' then
    select count(*) into v_expected_count
    from public.narcotics_count_template_items
    where template_id = v_template_id and active = true;

    select count(*) into v_entered_count
    from public.narcotics_count_lines
    where count_id = v_count_id and actual_quantity is not null;

    if v_expected_count = 0 then
      raise exception 'The assigned narcotics count template has no active items.';
    end if;
    if v_entered_count <> v_expected_count then
      raise exception 'Every narcotics line item must have a count before submission.';
    end if;
    if coalesce(p_attestation, false) = false then
      raise exception 'Electronic signature attestation is required.';
    end if;
    if nullif(btrim(p_signature_name), '') is null then
      raise exception 'Type your name to electronically sign the daily count.';
    end if;

    select signature_attestation into v_attestation
    from public.narcotics_agency_settings
    where agency_id = v_agency_id;

    v_attestation := coalesce(v_attestation,
      'I attest that I personally performed this narcotics inventory count and that the quantities entered are accurate to the best of my knowledge.');
    v_signed_at := now();

    select concat_ws('|',
      v_count_id::text,
      v_user_id::text,
      v_provider_id::text,
      p_vehicle_id::text,
      p_count_date::text,
      v_signed_at::text,
      btrim(p_signature_name),
      coalesce(jsonb_agg(
        jsonb_build_object(
          'item_id', template_item_id,
          'expected', expected_quantity,
          'actual', actual_quantity,
          'notes', notes
        ) order by sort_order, medication_name
      )::text, '[]')
    ) into v_signature_payload
    from public.narcotics_count_lines
    where count_id = v_count_id;

    update public.narcotics_counts c
    set status = 'submitted',
        submitted_by = v_user_id,
        submitted_provider_id = v_provider_id,
        signed_name = btrim(p_signature_name),
        signature_attestation = v_attestation,
        signed_at = v_signed_at,
        signature_hash = encode(digest(v_signature_payload, 'sha256'), 'hex'),
        has_discrepancy = exists (
          select 1 from public.narcotics_count_lines l
          where l.count_id = c.id and l.discrepancy = true
        ),
        updated_at = now()
    where c.id = v_count_id;
  end if;

  return v_count_id;
end;
$$;

revoke all on function public.save_narcotics_count(uuid,uuid,date,text,text,text,boolean,jsonb) from public, anon;
grant execute on function public.save_narcotics_count(uuid,uuid,date,text,text,text,boolean,jsonb) to authenticated;

-- -----------------------------------------------------------------------------
-- Updated-at / audit triggers
-- -----------------------------------------------------------------------------

do $$
declare
  t text;
begin
  foreach t in array array[
    'narcotics_count_templates','narcotics_count_template_items',
    'narcotics_agency_settings','narcotics_counts','narcotics_count_lines'
  ]
  loop
    if not exists (
      select 1 from pg_trigger
      where tgname = 'set_' || t || '_updated_at'
        and tgrelid = ('public.' || t)::regclass
        and not tgisinternal
    ) then
      execute format(
        'create trigger %I before update on public.%I for each row execute function private.set_updated_at()',
        'set_' || t || '_updated_at', t
      );
    end if;
  end loop;
end $$;

do $$
declare
  t text;
begin
  foreach t in array array[
    'narcotics_count_templates','narcotics_count_template_items',
    'narcotics_agency_settings','narcotics_counts','narcotics_count_lines'
  ]
  loop
    if not exists (
      select 1 from pg_trigger
      where tgname = 'audit_' || t
        and tgrelid = ('public.' || t)::regclass
        and not tgisinternal
    ) then
      execute format(
        'create trigger %I after insert or update or delete on public.%I for each row execute function private.audit_row_change()',
        'audit_' || t, t
      );
    end if;
  end loop;
end $$;

commit;

NOTIFY pgrst, 'reload schema';
