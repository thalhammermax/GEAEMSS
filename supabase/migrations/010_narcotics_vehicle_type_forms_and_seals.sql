-- GEAEMS Portal v0.6.2
-- Narcotics forms are assigned by vehicle type (not agency default), daily counts
-- capture a seal number, and seal changes require an explanation at submission.
-- Run after migrations 001 through 009.

begin;

-- -----------------------------------------------------------------------------
-- Vehicle-type based narcotics form assignment
-- -----------------------------------------------------------------------------

alter table public.vehicle_types
  add column if not exists narcotics_template_id uuid
  references public.narcotics_count_templates(id) on delete set null;

create index if not exists vehicle_types_narcotics_template_idx
  on public.vehicle_types(narcotics_template_id);

-- Agency default and vehicle override assignments from v0.6 are intentionally
-- retired. Historical counts retain the template_id snapshot they used.
update public.narcotics_agency_settings
set default_template_id = null
where default_template_id is not null;

update public.vehicles
set narcotics_template_id = null
where narcotics_template_id is not null;

comment on column public.narcotics_agency_settings.default_template_id is
  'Deprecated in v0.6.2. Daily narcotics templates are assigned by vehicle type.';
comment on column public.vehicles.narcotics_template_id is
  'Deprecated in v0.6.2. Daily narcotics templates are assigned by vehicle type.';
comment on column public.vehicle_types.narcotics_template_id is
  'Active system narcotics template automatically used by vehicles of this type.';

create or replace function private.validate_vehicle_type_narcotics_template()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.narcotics_template_id is not null and not exists (
    select 1
    from public.narcotics_count_templates t
    where t.id = new.narcotics_template_id
      and t.scope_type = 'system'
      and t.active = true
  ) then
    raise exception 'Vehicle types may only use an active GEAEMS System narcotics template.';
  end if;
  return new;
end;
$$;

revoke execute on function private.validate_vehicle_type_narcotics_template() from public, anon, authenticated;

drop trigger if exists validate_vehicle_type_narcotics_template on public.vehicle_types;
create trigger validate_vehicle_type_narcotics_template
before insert or update of narcotics_template_id on public.vehicle_types
for each row execute function private.validate_vehicle_type_narcotics_template();

-- -----------------------------------------------------------------------------
-- Seal tracking
-- -----------------------------------------------------------------------------

alter table public.narcotics_counts
  add column if not exists seal_number text,
  add column if not exists prior_seal_number text,
  add column if not exists seal_change_reason text;

comment on column public.narcotics_counts.seal_number is
  'Tamper-evident seal number observed at this daily count.';
comment on column public.narcotics_counts.prior_seal_number is
  'Seal number from the immediately preceding submitted count for this vehicle.';
comment on column public.narcotics_counts.seal_change_reason is
  'Required for new submissions when seal_number differs from prior_seal_number.';

create index if not exists narcotics_counts_vehicle_submitted_seal_idx
  on public.narcotics_counts(vehicle_id, count_date desc)
  where status = 'submitted';

-- -----------------------------------------------------------------------------
-- Save/sign RPC: template comes from vehicle type; seal change is validated.
-- -----------------------------------------------------------------------------

-- Remove the v0.6 overload so PostgREST exposes only the current contract.
drop function if exists public.save_narcotics_count(uuid,uuid,date,text,text,text,boolean,jsonb);

create or replace function public.save_narcotics_count(
  p_count_id uuid,
  p_vehicle_id uuid,
  p_count_date date,
  p_notes text,
  p_mode text,
  p_signature_name text,
  p_attestation boolean,
  p_seal_number text,
  p_seal_change_reason text,
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
  v_previous_seal text;
  v_current_seal text := nullif(btrim(p_seal_number), '');
  v_seal_change_reason text := nullif(btrim(p_seal_change_reason), '');
  v_seal_changed boolean := false;
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

  select v.agency_id, vt.narcotics_template_id
    into v_agency_id, v_template_id
  from public.vehicles v
  left join public.vehicle_types vt on vt.id = v.vehicle_type_id
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
    raise exception 'No narcotics count form is assigned to this vehicle type.';
  end if;

  if not exists (
    select 1
    from public.narcotics_count_templates t
    where t.id = v_template_id
      and t.active = true
      and t.scope_type = 'system'
  ) then
    raise exception 'The narcotics count form assigned to this vehicle type is not an active GEAEMS System form.';
  end if;

  if p_mode not in ('draft','submit') then
    raise exception 'Invalid save mode.';
  end if;

  select c.seal_number
    into v_previous_seal
  from public.narcotics_counts c
  where c.vehicle_id = p_vehicle_id
    and c.status = 'submitted'
    and c.count_date < p_count_date
  order by c.count_date desc, c.signed_at desc nulls last
  limit 1;

  v_previous_seal := nullif(btrim(v_previous_seal), '');
  v_seal_changed := v_previous_seal is not null
    and v_current_seal is not null
    and v_current_seal is distinct from v_previous_seal;

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
        status, started_by, started_provider_id, notes,
        seal_number, prior_seal_number, seal_change_reason
      ) values (
        v_agency_id, p_vehicle_id, v_template_id, p_count_date,
        'draft', v_user_id, v_provider_id, nullif(btrim(p_notes), ''),
        v_current_seal, v_previous_seal,
        case when v_seal_changed then v_seal_change_reason else null end
      ) returning id into v_count_id;
    end if;
  end if;

  update public.narcotics_counts
  set notes = nullif(btrim(p_notes), ''),
      template_id = v_template_id,
      seal_number = v_current_seal,
      prior_seal_number = v_previous_seal,
      seal_change_reason = case when v_seal_changed then v_seal_change_reason else null end,
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
      raise exception 'The assigned narcotics count form has no active items.';
    end if;
    if v_entered_count <> v_expected_count then
      raise exception 'Every narcotics line item must have a count before submission.';
    end if;
    if v_current_seal is null then
      raise exception 'Seal Number is required before submission.';
    end if;
    if v_seal_changed and v_seal_change_reason is null then
      raise exception 'The seal number changed from the previous submitted count. A reason for the seal change is required.';
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
      coalesce(v_current_seal, ''),
      coalesce(v_previous_seal, ''),
      coalesce(v_seal_change_reason, ''),
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
        seal_number = v_current_seal,
        prior_seal_number = v_previous_seal,
        seal_change_reason = case when v_seal_changed then v_seal_change_reason else null end,
        updated_at = now()
    where c.id = v_count_id;
  end if;

  return v_count_id;
end;
$$;

revoke all on function public.save_narcotics_count(uuid,uuid,date,text,text,text,boolean,text,text,jsonb) from public, anon;
grant execute on function public.save_narcotics_count(uuid,uuid,date,text,text,text,boolean,text,text,jsonb) to authenticated;

notify pgrst, 'reload schema';

commit;
