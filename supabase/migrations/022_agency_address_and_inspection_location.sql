-- GEAEMS Portal
-- Adds the canonical agency/headquarters address used as an optional inspection-location fallback.
-- Existing inspections are not modified.

begin;

alter table public.agencies
  add column if not exists address text;

insert into public.record_field_definitions
  (entity_type, field_key, label, field_type, source_type, builtin_column, field_group, help_text, enabled, required, system_locked, sort_order)
values
  (
    'agency',
    'address',
    'Agency address',
    'textarea',
    'builtin',
    'address',
    'Agency',
    'Primary agency/headquarters address. This can be used as the inspection Location when Agency Headquarters is selected.',
    true,
    false,
    false,
    30
  )
on conflict (entity_type, field_key) do update
set
  label = excluded.label,
  field_type = excluded.field_type,
  source_type = excluded.source_type,
  builtin_column = excluded.builtin_column,
  field_group = excluded.field_group,
  help_text = excluded.help_text,
  sort_order = excluded.sort_order;

commit;

notify pgrst, 'reload schema';
