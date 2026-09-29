-- GEAEMS Portal v0.6.6
-- Provider narcotics access + least-privilege historical log visibility.
-- Run after migrations 001 through 013.
--
-- Providers may participate in today's narcotics count for agencies where they
-- are active provider members. Full submitted-count history remains available
-- to System Administrators and the Agency Administrators assigned to that
-- agency. A provider may also read historical counts they personally started
-- or signed so their own electronic records remain visible.

begin;

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
      left join public.narcotics_agency_settings s on s.agency_id = c.agency_id
      where c.id = p_count_id
        and (
          private.is_system_admin()
          or (
            private.is_agency_admin()
            and private.has_agency_access(c.agency_id)
          )
          or (
            private.is_provider_member_of_agency(c.agency_id)
            and (
              c.count_date = ((now() at time zone coalesce(s.timezone, 'America/Chicago'))::date)
              or c.started_provider_id = private.my_provider_id()
              or c.submitted_provider_id = private.my_provider_id()
            )
          )
        )
    );
$$;

revoke execute on function private.can_view_narcotics_count(uuid) from public, anon;
grant execute on function private.can_view_narcotics_count(uuid) to authenticated;

-- Counts themselves now use the row-aware helper above instead of the broader
-- agency-visibility helper. Count lines already use can_view_narcotics_count().
drop policy if exists narcotics_counts_read on public.narcotics_counts;
create policy narcotics_counts_read on public.narcotics_counts
for select to authenticated
using ((select private.can_view_narcotics_count(id)));

notify pgrst, 'reload schema';

commit;
