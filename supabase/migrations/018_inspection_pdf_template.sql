-- GEAEMS Portal v0.9.2
-- Editable system-wide inspection PDF template settings.
-- Run after migrations 001 through 017.

begin;

create table if not exists public.inspection_pdf_template_settings (
  id text primary key default 'system' check (id = 'system'),
  organization_name text not null default 'GREATER ELGIN AREA EMS SYSTEM',
  report_title text not null default 'VEHICLE INSPECTION REPORT',
  accent_color text not null default '#14314A'
    check (accent_color ~ '^#[0-9A-Fa-f]{6}$'),
  heading_fill_color text not null default '#EDF2F7'
    check (heading_fill_color ~ '^#[0-9A-Fa-f]{6}$'),
  summary_heading text not null default 'Inspection Summary',
  notes_heading text not null default 'Overall Notes',
  checklist_heading text not null default 'Inspection Checklist',
  deficiencies_heading text not null default 'Deficiencies & Corrective Actions',
  footer_text text not null default 'Generated from GEAEMS Portal',

  show_summary boolean not null default true,
  show_vehicle_details boolean not null default true,
  show_result_badge boolean not null default true,
  show_form_version boolean not null default true,
  show_submitted_at boolean not null default true,
  show_next_due boolean not null default true,
  show_inspection_id boolean not null default true,
  show_overall_notes boolean not null default true,
  show_checklist boolean not null default true,
  show_requirements boolean not null default true,
  show_observed_values boolean not null default true,
  show_item_notes boolean not null default true,
  show_deficiencies boolean not null default true,
  show_correction_notes boolean not null default true,
  show_generation_timestamp boolean not null default true,
  show_page_numbers boolean not null default true,
  show_draft_watermark boolean not null default true,

  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into public.inspection_pdf_template_settings(id)
values ('system')
on conflict (id) do nothing;

alter table public.inspection_pdf_template_settings enable row level security;

grant select, insert, update on public.inspection_pdf_template_settings to authenticated;

drop policy if exists inspection_pdf_template_read on public.inspection_pdf_template_settings;
drop policy if exists inspection_pdf_template_insert on public.inspection_pdf_template_settings;
drop policy if exists inspection_pdf_template_update on public.inspection_pdf_template_settings;

create policy inspection_pdf_template_read
on public.inspection_pdf_template_settings
for select to authenticated
using ((select private.is_user_active()));

create policy inspection_pdf_template_insert
on public.inspection_pdf_template_settings
for insert to authenticated
with check (
  id = 'system'
  and (select private.is_system_admin())
);

create policy inspection_pdf_template_update
on public.inspection_pdf_template_settings
for update to authenticated
using ((select private.is_system_admin()))
with check (
  id = 'system'
  and (select private.is_system_admin())
);

commit;

NOTIFY pgrst, 'reload schema';
