-- GEAEMS Portal v0.10.3
-- Make daily narcotics-count requirements operator-controlled and module-aware.
-- Run after migrations 001 through 020.

begin;

-- v0.6 forced all ALS / critical-care vehicle types to require a daily narcotics
-- count. That made the Fleet checkbox impossible to turn off because every UPDATE
-- was rewritten back to true by this trigger.
drop trigger if exists enforce_als_narcotics_requirement on public.vehicles;
drop function if exists private.enforce_als_narcotics_requirement();

comment on column public.vehicles.narcotics_count_required is
  'Operator-controlled flag. When true, this apparatus requires a signed daily narcotics count. The flag is not automatically forced by vehicle type.';

-- The Narcotics module is intentionally disabled during the current staged
-- rollout. Clear stale requirements so hidden / disabled Narcotics workflows do
-- not leave production vehicles marked as requiring daily counts.
update public.vehicles
set narcotics_count_required = false
where narcotics_count_required = true
  and coalesce((
    select enabled
    from public.system_module_settings
    where module_key = 'narcotics'
  ), false) = false;

commit;

NOTIFY pgrst, 'reload schema';
