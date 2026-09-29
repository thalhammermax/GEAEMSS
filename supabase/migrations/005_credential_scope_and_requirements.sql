-- GEAEMS Portal v0.4
-- System- and agency-owned credential definitions, scoped requirements,
-- and credential-type-aware RLS for shared providers.
-- Run after migrations 001 through 004.

begin;

-- -----------------------------------------------------------------------------
-- Credential ownership
-- -----------------------------------------------------------------------------

alter table public.credential_types
  add column if not exists scope_type text not null default 'system',
  add column if not exists agency_id uuid references public.agencies(id) on delete cascade,
  add column if not exists created_by uuid references auth.users(id) on delete set null;

alter table public.credential_types
  drop constraint if exists credential_types_scope_check;

alter table public.credential_types
  add constraint credential_types_scope_check check (
    (scope_type = 'system' and agency_id is null)
    or
    (scope_type = 'agency' and agency_id is not null)
  );

-- Existing v0.3 credential definitions are System credentials.
update public.credential_types
set scope_type = 'system', agency_id = null
where scope_type is null or (scope_type = 'system' and agency_id is not null);

-- Credential names/codes only need to be unique inside their ownership scope.
alter table public.credential_types drop constraint if exists credential_types_code_key;
alter table public.credential_types drop constraint if exists credential_types_name_key;

drop index if exists public.credential_types_system_code_unique;
drop index if exists public.credential_types_system_name_unique;
drop index if exists public.credential_types_agency_code_unique;
drop index if exists public.credential_types_agency_name_unique;

create unique index credential_types_system_code_unique
  on public.credential_types (lower(code))
  where scope_type = 'system';

create unique index credential_types_system_name_unique
  on public.credential_types (lower(name))
  where scope_type = 'system';

create unique index credential_types_agency_code_unique
  on public.credential_types (agency_id, lower(code))
  where scope_type = 'agency';

create unique index credential_types_agency_name_unique
  on public.credential_types (agency_id, lower(name))
  where scope_type = 'agency';

create index if not exists credential_types_agency_idx on public.credential_types(agency_id);

-- -----------------------------------------------------------------------------
-- Authorization helpers
-- -----------------------------------------------------------------------------

create or replace function private.provider_is_affiliated_with_agency(
  p_provider_id uuid,
  p_agency_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.provider_agencies pa
    where pa.provider_id = p_provider_id
      and pa.agency_id = p_agency_id
      and pa.active = true
  );
$$;

create or replace function private.credential_type_available_to_agency(
  p_credential_type_id uuid,
  p_agency_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.credential_types ct
    where ct.id = p_credential_type_id
      and (
        ct.scope_type = 'system'
        or (ct.scope_type = 'agency' and ct.agency_id = p_agency_id)
      )
  );
$$;

create or replace function private.provider_may_use_credential_type(
  p_provider_id uuid,
  p_credential_type_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.credential_types ct
    where ct.id = p_credential_type_id
      and (
        ct.scope_type = 'system'
        or (
          ct.scope_type = 'agency'
          and private.provider_is_affiliated_with_agency(p_provider_id, ct.agency_id)
        )
      )
  );
$$;

create or replace function private.can_view_provider_credential(
  p_provider_id uuid,
  p_credential_type_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.is_user_active()
    and (
      private.is_system_admin()
      or private.is_self_provider(p_provider_id)
      or (
        private.is_agency_admin()
        and exists (
          select 1
          from public.credential_types ct
          where ct.id = p_credential_type_id
            and (
              (
                ct.scope_type = 'system'
                and exists (
                  select 1
                  from public.provider_agencies pa
                  join public.user_agency_access uaa on uaa.agency_id = pa.agency_id
                  where pa.provider_id = p_provider_id
                    and pa.active = true
                    and uaa.user_id = (select auth.uid())
                )
              )
              or (
                ct.scope_type = 'agency'
                and private.provider_is_affiliated_with_agency(p_provider_id, ct.agency_id)
                and private.has_agency_access(ct.agency_id)
              )
            )
        )
      )
    );
$$;

create or replace function private.can_manage_provider_credential(
  p_provider_id uuid,
  p_credential_type_id uuid
)
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
          from public.credential_types ct
          where ct.id = p_credential_type_id
            and (
              (
                ct.scope_type = 'system'
                and exists (
                  select 1
                  from public.provider_agencies pa
                  join public.user_agency_access uaa on uaa.agency_id = pa.agency_id
                  where pa.provider_id = p_provider_id
                    and pa.active = true
                    and uaa.user_id = (select auth.uid())
                    and uaa.can_manage_credentials = true
                )
              )
              or (
                ct.scope_type = 'agency'
                and private.provider_is_affiliated_with_agency(p_provider_id, ct.agency_id)
                and private.can_manage_agency_credentials(ct.agency_id)
              )
            )
        )
      )
    );
$$;

-- Preserve the original one-argument helper for older app paths. It means the
-- administrator can manage at least one credential context for the provider.
create or replace function private.can_manage_provider_credentials(p_provider_id uuid)
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
          from public.provider_agencies pa
          join public.user_agency_access uaa on uaa.agency_id = pa.agency_id
          where pa.provider_id = p_provider_id
            and pa.active = true
            and uaa.user_id = (select auth.uid())
            and uaa.can_manage_credentials = true
        )
      )
    );
$$;

revoke execute on function private.provider_is_affiliated_with_agency(uuid, uuid) from public, anon;
revoke execute on function private.credential_type_available_to_agency(uuid, uuid) from public, anon;
revoke execute on function private.provider_may_use_credential_type(uuid, uuid) from public, anon;
revoke execute on function private.can_view_provider_credential(uuid, uuid) from public, anon;
revoke execute on function private.can_manage_provider_credential(uuid, uuid) from public, anon;

grant execute on function private.provider_is_affiliated_with_agency(uuid, uuid) to authenticated;
grant execute on function private.credential_type_available_to_agency(uuid, uuid) to authenticated;
grant execute on function private.provider_may_use_credential_type(uuid, uuid) to authenticated;
grant execute on function private.can_view_provider_credential(uuid, uuid) to authenticated;
grant execute on function private.can_manage_provider_credential(uuid, uuid) to authenticated;

-- Credential ownership is immutable after creation. This prevents a credential
-- with existing history/requirements from silently changing compliance scope.
create or replace function private.guard_credential_type_ownership_change()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if old.scope_type is distinct from new.scope_type
     or old.agency_id is distinct from new.agency_id then
    raise exception 'Credential ownership cannot be changed after creation';
  end if;
  return new;
end;
$$;

revoke execute on function private.guard_credential_type_ownership_change() from public, anon, authenticated;

drop trigger if exists credential_types_ownership_guard on public.credential_types;
create trigger credential_types_ownership_guard
before update of scope_type, agency_id on public.credential_types
for each row execute function private.guard_credential_type_ownership_change();

-- A System requirement may only reference a System credential. An Agency
-- requirement may reference a System credential or a credential owned by that
-- same agency.
create or replace function private.guard_credential_requirement_scope()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_type_scope text;
  v_type_agency uuid;
begin
  select scope_type, agency_id
  into v_type_scope, v_type_agency
  from public.credential_types
  where id = new.credential_type_id;

  if v_type_scope is null then
    raise exception 'Credential type not found';
  end if;

  if new.scope_type = 'system' and v_type_scope <> 'system' then
    raise exception 'Agency credentials cannot be required system-wide';
  end if;

  if new.scope_type = 'agency'
     and v_type_scope = 'agency'
     and v_type_agency is distinct from new.agency_id then
    raise exception 'Agency credential can only be required by its owning agency';
  end if;

  return new;
end;
$$;

revoke execute on function private.guard_credential_requirement_scope() from public, anon, authenticated;

drop trigger if exists credential_requirements_scope_guard on public.credential_requirements;
create trigger credential_requirements_scope_guard
before insert or update of credential_type_id, scope_type, agency_id
on public.credential_requirements
for each row execute function private.guard_credential_requirement_scope();

-- -----------------------------------------------------------------------------
-- Credential type RLS
-- -----------------------------------------------------------------------------

drop policy if exists credential_types_read on public.credential_types;
drop policy if exists credential_types_admin_write on public.credential_types;
drop policy if exists credential_types_insert on public.credential_types;
drop policy if exists credential_types_update on public.credential_types;
drop policy if exists credential_types_delete on public.credential_types;

create policy credential_types_read on public.credential_types
for select to authenticated
using (
  (select private.is_user_active())
  and (
    scope_type = 'system'
    or (select private.is_system_admin())
    or (agency_id is not null and (select private.has_agency_access(agency_id)))
    or (
      agency_id is not null
      and exists (
        select 1
        from public.provider_agencies pa
        where pa.provider_id = (select private.my_provider_id())
          and pa.agency_id = credential_types.agency_id
          and pa.active = true
      )
    )
  )
);

create policy credential_types_insert on public.credential_types
for insert to authenticated
with check (
  (select private.is_system_admin())
  or (
    scope_type = 'agency'
    and agency_id is not null
    and (select private.can_manage_agency_credentials(agency_id))
  )
);

create policy credential_types_update on public.credential_types
for update to authenticated
using (
  (select private.is_system_admin())
  or (
    scope_type = 'agency'
    and agency_id is not null
    and (select private.can_manage_agency_credentials(agency_id))
  )
)
with check (
  (select private.is_system_admin())
  or (
    scope_type = 'agency'
    and agency_id is not null
    and (select private.can_manage_agency_credentials(agency_id))
  )
);

create policy credential_types_delete on public.credential_types
for delete to authenticated
using (
  (select private.is_system_admin())
  or (
    scope_type = 'agency'
    and agency_id is not null
    and (select private.can_manage_agency_credentials(agency_id))
  )
);

-- -----------------------------------------------------------------------------
-- Requirement RLS
-- -----------------------------------------------------------------------------

drop policy if exists credential_requirements_read on public.credential_requirements;
drop policy if exists credential_requirements_admin_write on public.credential_requirements;
drop policy if exists credential_requirements_insert on public.credential_requirements;
drop policy if exists credential_requirements_update on public.credential_requirements;
drop policy if exists credential_requirements_delete on public.credential_requirements;

create policy credential_requirements_read on public.credential_requirements
for select to authenticated
using (
  (select private.is_user_active())
  and (
    (select private.is_system_admin())
    or scope_type = 'system'
    or (
      scope_type = 'agency'
      and agency_id is not null
      and (
        (select private.has_agency_access(agency_id))
        or exists (
          select 1
          from public.provider_agencies pa
          where pa.agency_id = credential_requirements.agency_id
            and pa.provider_id = (select private.my_provider_id())
            and pa.active = true
        )
      )
    )
  )
);

create policy credential_requirements_insert on public.credential_requirements
for insert to authenticated
with check (
  (select private.is_system_admin())
  or (
    scope_type = 'agency'
    and agency_id is not null
    and (select private.can_manage_agency_credentials(agency_id))
    and (select private.credential_type_available_to_agency(credential_type_id, agency_id))
  )
);

create policy credential_requirements_update on public.credential_requirements
for update to authenticated
using (
  (select private.is_system_admin())
  or (
    scope_type = 'agency'
    and agency_id is not null
    and (select private.can_manage_agency_credentials(agency_id))
  )
)
with check (
  (select private.is_system_admin())
  or (
    scope_type = 'agency'
    and agency_id is not null
    and (select private.can_manage_agency_credentials(agency_id))
    and (select private.credential_type_available_to_agency(credential_type_id, agency_id))
  )
);

create policy credential_requirements_delete on public.credential_requirements
for delete to authenticated
using (
  (select private.is_system_admin())
  or (
    scope_type = 'agency'
    and agency_id is not null
    and (select private.can_manage_agency_credentials(agency_id))
  )
);

-- -----------------------------------------------------------------------------
-- Credential record/submission RLS becomes credential-type aware.
-- -----------------------------------------------------------------------------

drop policy if exists provider_credentials_read on public.provider_credentials;
drop policy if exists provider_credentials_admin_insert on public.provider_credentials;
drop policy if exists provider_credentials_admin_update on public.provider_credentials;
drop policy if exists provider_credentials_admin_delete on public.provider_credentials;

create policy provider_credentials_read on public.provider_credentials
for select to authenticated
using ((select private.can_view_provider_credential(provider_id, credential_type_id)));

create policy provider_credentials_admin_insert on public.provider_credentials
for insert to authenticated
with check ((select private.can_manage_provider_credential(provider_id, credential_type_id)));

create policy provider_credentials_admin_update on public.provider_credentials
for update to authenticated
using ((select private.can_manage_provider_credential(provider_id, credential_type_id)))
with check ((select private.can_manage_provider_credential(provider_id, credential_type_id)));

create policy provider_credentials_admin_delete on public.provider_credentials
for delete to authenticated
using ((select private.is_system_admin()));

-- Submission policies.
drop policy if exists credential_submissions_read on public.credential_submissions;
drop policy if exists credential_submissions_insert on public.credential_submissions;
drop policy if exists credential_submissions_provider_withdraw on public.credential_submissions;
drop policy if exists credential_submissions_admin_update on public.credential_submissions;
drop policy if exists credential_submissions_admin_delete on public.credential_submissions;

create policy credential_submissions_read on public.credential_submissions
for select to authenticated
using ((select private.can_view_provider_credential(provider_id, credential_type_id)));

create policy credential_submissions_insert on public.credential_submissions
for insert to authenticated
with check (
  submitted_by = (select auth.uid())
  and (
    (
      provider_id = (select private.my_provider_id())
      and (select private.provider_may_use_credential_type(provider_id, credential_type_id))
    )
    or (select private.can_manage_provider_credential(provider_id, credential_type_id))
  )
);

create policy credential_submissions_provider_withdraw on public.credential_submissions
for update to authenticated
using (
  provider_id = (select private.my_provider_id())
  and submitted_by = (select auth.uid())
  and status in ('pending', 'changes_requested')
)
with check (
  provider_id = (select private.my_provider_id())
  and submitted_by = (select auth.uid())
  and status in ('pending', 'withdrawn')
  and (select private.provider_may_use_credential_type(provider_id, credential_type_id))
);

create policy credential_submissions_admin_update on public.credential_submissions
for update to authenticated
using ((select private.can_manage_provider_credential(provider_id, credential_type_id)))
with check ((select private.can_manage_provider_credential(provider_id, credential_type_id)));

create policy credential_submissions_admin_delete on public.credential_submissions
for delete to authenticated using ((select private.is_system_admin()));

-- Provider and credential-type identity are historical keys and cannot be moved
-- between people or definitions after a record/submission is created.
create or replace function private.guard_credential_record_identity_change()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if old.provider_id is distinct from new.provider_id
     or old.credential_type_id is distinct from new.credential_type_id then
    raise exception 'Credential provider and credential type cannot be changed after creation';
  end if;
  return new;
end;
$$;

revoke execute on function private.guard_credential_record_identity_change() from public, anon, authenticated;

drop trigger if exists provider_credentials_identity_guard on public.provider_credentials;
create trigger provider_credentials_identity_guard
before update of provider_id, credential_type_id on public.provider_credentials
for each row execute function private.guard_credential_record_identity_change();

drop trigger if exists credential_submissions_identity_guard on public.credential_submissions;
create trigger credential_submissions_identity_guard
before update of provider_id, credential_type_id on public.credential_submissions
for each row execute function private.guard_credential_record_identity_change();

-- Credential document metadata and notification history also respect credential ownership.
drop policy if exists credential_documents_read on public.credential_documents;
drop policy if exists credential_documents_insert on public.credential_documents;
drop policy if exists credential_documents_admin_update on public.credential_documents;
drop policy if exists credential_documents_delete on public.credential_documents;

create policy credential_documents_read on public.credential_documents
for select to authenticated
using (
  (provider_credential_id is not null and exists (
    select 1 from public.provider_credentials pc
    where pc.id = credential_documents.provider_credential_id
      and (select private.can_view_provider_credential(pc.provider_id, pc.credential_type_id))
  ))
  or
  (submission_id is not null and exists (
    select 1 from public.credential_submissions cs
    where cs.id = credential_documents.submission_id
      and (select private.can_view_provider_credential(cs.provider_id, cs.credential_type_id))
  ))
);

create policy credential_documents_insert on public.credential_documents
for insert to authenticated
with check (
  uploaded_by = (select auth.uid())
  and (
    (provider_credential_id is not null and exists (
      select 1 from public.provider_credentials pc
      where pc.id = credential_documents.provider_credential_id
        and (select private.can_manage_provider_credential(pc.provider_id, pc.credential_type_id))
    ))
    or
    (submission_id is not null and exists (
      select 1 from public.credential_submissions cs
      where cs.id = credential_documents.submission_id
        and (
          (
            cs.provider_id = (select private.my_provider_id())
            and (select private.provider_may_use_credential_type(cs.provider_id, cs.credential_type_id))
          )
          or (select private.can_manage_provider_credential(cs.provider_id, cs.credential_type_id))
        )
    ))
  )
);

create policy credential_documents_admin_update on public.credential_documents
for update to authenticated
using (
  (provider_credential_id is not null and exists (
    select 1 from public.provider_credentials pc
    where pc.id = credential_documents.provider_credential_id
      and (select private.can_manage_provider_credential(pc.provider_id, pc.credential_type_id))
  ))
  or
  (submission_id is not null and exists (
    select 1 from public.credential_submissions cs
    where cs.id = credential_documents.submission_id
      and (select private.can_manage_provider_credential(cs.provider_id, cs.credential_type_id))
  ))
)
with check (
  (provider_credential_id is not null and exists (
    select 1 from public.provider_credentials pc
    where pc.id = credential_documents.provider_credential_id
      and (select private.can_manage_provider_credential(pc.provider_id, pc.credential_type_id))
  ))
  or
  (submission_id is not null and exists (
    select 1 from public.credential_submissions cs
    where cs.id = credential_documents.submission_id
      and (select private.can_manage_provider_credential(cs.provider_id, cs.credential_type_id))
  ))
);

create policy credential_documents_delete on public.credential_documents
for delete to authenticated
using (
  (select private.is_system_admin())
  or
  (submission_id is not null and exists (
    select 1 from public.credential_submissions cs
    where cs.id = credential_documents.submission_id
      and (
        (cs.provider_id = (select private.my_provider_id()) and cs.status = 'pending')
        or (select private.can_manage_provider_credential(cs.provider_id, cs.credential_type_id))
      )
  ))
);

drop policy if exists notification_history_read on public.notification_history;
create policy notification_history_read on public.notification_history
for select to authenticated
using ((select private.can_view_provider_credential(provider_id, credential_type_id)));

-- -----------------------------------------------------------------------------
-- Review RPCs use credential-type-aware authorization.
-- -----------------------------------------------------------------------------

create or replace function public.approve_credential_submission(
  p_submission_id uuid,
  p_review_notes text default null
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_submission public.credential_submissions%rowtype;
  v_old_credential_id uuid;
  v_new_credential_id uuid;
begin
  select * into v_submission
  from public.credential_submissions
  where id = p_submission_id
  for update;

  if not found then
    raise exception 'Credential submission not found';
  end if;

  if v_submission.status <> 'pending' and v_submission.status <> 'changes_requested' then
    raise exception 'Credential submission is not reviewable in status %', v_submission.status;
  end if;

  if not private.can_manage_provider_credential(v_submission.provider_id, v_submission.credential_type_id) then
    raise exception 'Not authorized to approve this credential';
  end if;

  select id into v_old_credential_id
  from public.provider_credentials
  where provider_id = v_submission.provider_id
    and credential_type_id = v_submission.credential_type_id
    and is_current = true
    and verification_status = 'verified'
  for update;

  if v_old_credential_id is not null then
    update public.provider_credentials
    set is_current = false,
        updated_at = now()
    where id = v_old_credential_id;
  end if;

  insert into public.provider_credentials (
    provider_id, credential_type_id, credential_number, issue_date,
    expiration_date, verification_status, is_current, verified_by,
    verified_at, source, supersedes_credential_id, created_by
  ) values (
    v_submission.provider_id, v_submission.credential_type_id,
    v_submission.credential_number, v_submission.issue_date,
    v_submission.expiration_date, 'verified', true,
    (select auth.uid()), now(), 'provider_submission',
    v_old_credential_id, v_submission.submitted_by
  ) returning id into v_new_credential_id;

  update public.credential_documents
  set provider_credential_id = v_new_credential_id,
      submission_id = null
  where submission_id = p_submission_id;

  update public.credential_submissions
  set status = 'approved', reviewed_by = (select auth.uid()),
      reviewed_at = now(), review_notes = p_review_notes,
      resulting_credential_id = v_new_credential_id, updated_at = now()
  where id = p_submission_id;

  return v_new_credential_id;
end;
$$;

create or replace function public.reject_credential_submission(
  p_submission_id uuid,
  p_review_notes text
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_provider_id uuid;
  v_credential_type_id uuid;
begin
  select provider_id, credential_type_id
  into v_provider_id, v_credential_type_id
  from public.credential_submissions
  where id = p_submission_id
  for update;

  if v_provider_id is null then
    raise exception 'Credential submission not found';
  end if;

  if not private.can_manage_provider_credential(v_provider_id, v_credential_type_id) then
    raise exception 'Not authorized to reject this credential';
  end if;

  update public.credential_submissions
  set status = 'rejected', reviewed_by = (select auth.uid()),
      reviewed_at = now(), review_notes = p_review_notes, updated_at = now()
  where id = p_submission_id
    and status in ('pending', 'changes_requested');
end;
$$;

-- -----------------------------------------------------------------------------
-- Compliance view: active/compliance-counting providers only. Agency-level
-- requirements use the provider's agency-specific level when one is set.
-- -----------------------------------------------------------------------------

create or replace view public.provider_compliance
with (security_invoker = true)
as
with required_pairs as (
  select distinct p.id as provider_id, cr.credential_type_id
  from public.providers p
  join public.provider_statuses ps on ps.id = p.provider_status_id
  join public.credential_requirements cr
    on cr.scope_type = 'system'
   and cr.required = true
   and (cr.provider_level_id is null or cr.provider_level_id = p.provider_level_id)
   and (cr.effective_start_date is null or cr.effective_start_date <= current_date)
   and (cr.effective_end_date is null or cr.effective_end_date >= current_date)
  where ps.counts_toward_compliance = true

  union

  select distinct p.id as provider_id, cr.credential_type_id
  from public.providers p
  join public.provider_statuses ps on ps.id = p.provider_status_id
  join public.provider_agencies pa
    on pa.provider_id = p.id
   and pa.active = true
  join public.credential_requirements cr
    on cr.scope_type = 'agency'
   and cr.agency_id = pa.agency_id
   and cr.required = true
   and (
     cr.provider_level_id is null
     or cr.provider_level_id = coalesce(pa.agency_provider_level_id, p.provider_level_id)
   )
   and (cr.effective_start_date is null or cr.effective_start_date <= current_date)
   and (cr.effective_end_date is null or cr.effective_end_date >= current_date)
  where ps.counts_toward_compliance = true
)
select
  rp.provider_id,
  p.first_name,
  p.last_name,
  p.provider_level_id,
  rp.credential_type_id,
  ct.code as credential_code,
  ct.name as credential_name,
  pc.id as provider_credential_id,
  pc.expiration_date,
  case
    when pc.id is null then 'MISSING'
    when pc.expiration_date is not null and pc.expiration_date < current_date then 'EXPIRED'
    when pc.expiration_date is not null
      and pc.expiration_date <= current_date + coalesce((select max(d) from unnest(ct.warning_days) d), 90)
      then 'EXPIRING_SOON'
    else 'CURRENT'
  end as compliance_status,
  case when pc.expiration_date is null then null else (pc.expiration_date - current_date) end as days_remaining,
  ct.scope_type as credential_scope_type,
  ct.agency_id as credential_agency_id
from required_pairs rp
join public.providers p on p.id = rp.provider_id
join public.credential_types ct on ct.id = rp.credential_type_id
left join public.provider_credentials pc
  on pc.provider_id = rp.provider_id
 and pc.credential_type_id = rp.credential_type_id
 and pc.is_current = true
 and pc.verification_status = 'verified';

grant select on public.provider_compliance to authenticated;

commit;

NOTIFY pgrst, 'reload schema';
