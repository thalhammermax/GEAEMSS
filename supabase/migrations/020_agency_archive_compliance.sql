-- GEAEMS Portal v0.10.2
-- Agency archival isolation for vehicle licensing and inspection compliance.
-- Run after migrations 001 through 019.

begin;

create or replace view public.vehicle_license_compliance
with (security_invoker = true)
as
with required_pairs as (
  select distinct v.id as vehicle_id, r.vehicle_license_type_id
  from public.vehicles v
  join public.agencies a on a.id = v.agency_id and a.active = true
  join public.vehicle_statuses vs on vs.id = v.vehicle_status_id
  join public.vehicle_license_requirements r
    on r.scope_type = 'system'
   and r.required = true
   and (r.vehicle_type_id is null or r.vehicle_type_id = v.vehicle_type_id)
   and (r.effective_start_date is null or r.effective_start_date <= current_date)
   and (r.effective_end_date is null or r.effective_end_date >= current_date)
  where v.active = true and vs.counts_toward_compliance = true

  union

  select distinct v.id as vehicle_id, r.vehicle_license_type_id
  from public.vehicles v
  join public.agencies a on a.id = v.agency_id and a.active = true
  join public.vehicle_statuses vs on vs.id = v.vehicle_status_id
  join public.vehicle_license_requirements r
    on r.scope_type = 'agency'
   and r.agency_id = v.agency_id
   and r.required = true
   and (r.vehicle_type_id is null or r.vehicle_type_id = v.vehicle_type_id)
   and (r.effective_start_date is null or r.effective_start_date <= current_date)
   and (r.effective_end_date is null or r.effective_end_date >= current_date)
  where v.active = true and vs.counts_toward_compliance = true
)
select
  rp.vehicle_id,
  v.agency_id,
  v.unit_number,
  v.vin,
  rp.vehicle_license_type_id,
  vlt.code as license_code,
  vlt.name as license_name,
  vl.id as vehicle_license_id,
  vl.expiration_date,
  case
    when vl.id is null then 'MISSING'
    when vl.expiration_date is not null and vl.expiration_date < current_date then 'EXPIRED'
    when vl.expiration_date is not null
      and vl.expiration_date <= current_date + coalesce((select max(d) from unnest(vlt.warning_days) d), 90)
      then 'EXPIRING_SOON'
    else 'CURRENT'
  end as compliance_status,
  case when vl.expiration_date is null then null else (vl.expiration_date - current_date) end as days_remaining
from required_pairs rp
join public.vehicles v on v.id = rp.vehicle_id
join public.vehicle_license_types vlt on vlt.id = rp.vehicle_license_type_id
left join public.vehicle_licenses vl
  on vl.vehicle_id = rp.vehicle_id
 and vl.vehicle_license_type_id = rp.vehicle_license_type_id
 and vl.is_current = true
 and vl.verification_status = 'verified';

grant select on public.vehicle_license_compliance to authenticated;

create or replace view public.vehicle_inspection_compliance
with (security_invoker = true)
as
with required_pairs as (
  select distinct v.id as vehicle_id, r.inspection_type_id
  from public.vehicles v
  join public.agencies a on a.id = v.agency_id and a.active = true
  join public.vehicle_statuses vs on vs.id = v.vehicle_status_id
  join public.vehicle_inspection_requirements r
    on r.scope_type = 'system'
   and r.required = true
   and (r.vehicle_type_id is null or r.vehicle_type_id = v.vehicle_type_id)
   and (r.effective_start_date is null or r.effective_start_date <= current_date)
   and (r.effective_end_date is null or r.effective_end_date >= current_date)
  where v.active = true and vs.counts_toward_compliance = true

  union

  select distinct v.id as vehicle_id, r.inspection_type_id
  from public.vehicles v
  join public.agencies a on a.id = v.agency_id and a.active = true
  join public.vehicle_statuses vs on vs.id = v.vehicle_status_id
  join public.vehicle_inspection_requirements r
    on r.scope_type = 'agency'
   and r.agency_id = v.agency_id
   and r.required = true
   and (r.vehicle_type_id is null or r.vehicle_type_id = v.vehicle_type_id)
   and (r.effective_start_date is null or r.effective_start_date <= current_date)
   and (r.effective_end_date is null or r.effective_end_date >= current_date)
  where v.active = true and vs.counts_toward_compliance = true
)
select
  rp.vehicle_id,
  v.agency_id,
  v.unit_number,
  v.vin,
  rp.inspection_type_id,
  it.code as inspection_code,
  it.name as inspection_name,
  lis.id as latest_inspection_id,
  lis.inspection_date as latest_inspection_date,
  lis.result as latest_result,
  s.next_due_date,
  case
    when lis.result in ('failed', 'out_of_service') then 'FAILED'
    when s.id is null and lis.id is null then 'MISSING'
    when s.id is null then 'SCHEDULE_MISSING'
    when s.next_due_date < current_date then 'OVERDUE'
    when s.next_due_date <= current_date + coalesce((select max(d) from unnest(it.warning_days) d), 30)
      then 'DUE_SOON'
    else 'CURRENT'
  end as compliance_status,
  case when s.next_due_date is null then null else (s.next_due_date - current_date) end as days_until_due
from required_pairs rp
join public.vehicles v on v.id = rp.vehicle_id
join public.inspection_types it on it.id = rp.inspection_type_id
left join public.vehicle_inspection_schedules s
  on s.vehicle_id = rp.vehicle_id
 and s.inspection_type_id = rp.inspection_type_id
 and s.active = true
left join lateral (
  select vi.*
  from public.vehicle_inspections vi
  where vi.vehicle_id = rp.vehicle_id
    and vi.inspection_type_id = rp.inspection_type_id
  order by vi.inspection_date desc, vi.created_at desc
  limit 1
) lis on true;

grant select on public.vehicle_inspection_compliance to authenticated;

commit;

NOTIFY pgrst, 'reload schema';
