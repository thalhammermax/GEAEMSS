-- GEAEMS Portal v0.8
-- Provider credential self-service, secure document storage, and submission finalization.
-- Run after migrations 001 through 015.

begin;

-- -----------------------------------------------------------------------------
-- Submission lifecycle and provider notes
-- -----------------------------------------------------------------------------

alter table public.credential_submissions
  add column if not exists provider_notes text;

alter table public.credential_submissions
  drop constraint if exists credential_submissions_status_check;

alter table public.credential_submissions
  add constraint credential_submissions_status_check check (
    status in ('draft', 'pending', 'approved', 'rejected', 'changes_requested', 'withdrawn')
  );

-- Providers may only insert their own submissions as drafts. Final transition to
-- pending/approved is performed by the validation RPC below.
drop policy if exists credential_submissions_insert on public.credential_submissions;
create policy credential_submissions_insert on public.credential_submissions
for insert to authenticated
with check (
  submitted_by = (select auth.uid())
  and (
    (
      provider_id = (select private.my_provider_id())
      and status = 'draft'
      and (select private.provider_may_use_credential_type(provider_id, credential_type_id))
    )
    or (select private.can_manage_provider_credential(provider_id, credential_type_id))
  )
);

-- Providers can edit an unfinished draft or a submission returned for changes,
-- or withdraw an open submission. They cannot promote themselves to pending or
-- approved by updating the row directly.
drop policy if exists credential_submissions_provider_withdraw on public.credential_submissions;
create policy credential_submissions_provider_withdraw on public.credential_submissions
for update to authenticated
using (
  provider_id = (select private.my_provider_id())
  and submitted_by = (select auth.uid())
  and status in ('draft', 'pending', 'changes_requested')
)
with check (
  provider_id = (select private.my_provider_id())
  and submitted_by = (select auth.uid())
  and status in ('draft', 'changes_requested', 'withdrawn')
  and (select private.provider_may_use_credential_type(provider_id, credential_type_id))
);

-- Tighten provider document metadata writes to submissions that are still
-- editable. Administrative users retain their credential-management rights.
drop policy if exists credential_documents_insert on public.credential_documents;
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
            and cs.submitted_by = (select auth.uid())
            and cs.status in ('draft', 'changes_requested')
            and (select private.provider_may_use_credential_type(cs.provider_id, cs.credential_type_id))
          )
          or (select private.can_manage_provider_credential(cs.provider_id, cs.credential_type_id))
        )
    ))
  )
);

drop policy if exists credential_documents_delete on public.credential_documents;
create policy credential_documents_delete on public.credential_documents
for delete to authenticated
using (
  (select private.is_system_admin())
  or
  (submission_id is not null and exists (
    select 1 from public.credential_submissions cs
    where cs.id = credential_documents.submission_id
      and (
        (
          cs.provider_id = (select private.my_provider_id())
          and cs.submitted_by = (select auth.uid())
          and cs.status in ('draft', 'changes_requested')
        )
        or (select private.can_manage_provider_credential(cs.provider_id, cs.credential_type_id))
      )
  ))
);

-- -----------------------------------------------------------------------------
-- Secure credential-document storage bucket and authorization helpers
-- Object path format: <provider_uuid>/<submission_uuid>/<filename>
-- -----------------------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'credential-documents',
  'credential-documents',
  false,
  10485760,
  array['application/pdf','image/jpeg','image/png','image/webp']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create or replace function private.credential_storage_submission_id(p_name text)
returns uuid
language plpgsql
immutable
security definer
set search_path = ''
as $$
begin
  if split_part(p_name, '/', 2) = '' then
    return null;
  end if;
  return split_part(p_name, '/', 2)::uuid;
exception when others then
  return null;
end;
$$;

create or replace function private.can_read_credential_storage_object(p_name text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_submission_id uuid;
  v_provider_id uuid;
  v_credential_type_id uuid;
begin
  v_submission_id := private.credential_storage_submission_id(p_name);
  if v_submission_id is null then return false; end if;

  select provider_id, credential_type_id
    into v_provider_id, v_credential_type_id
  from public.credential_submissions
  where id = v_submission_id;

  if v_provider_id is null then return false; end if;
  return private.can_view_provider_credential(v_provider_id, v_credential_type_id);
end;
$$;

create or replace function private.can_write_credential_storage_object(p_name text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_submission_id uuid;
  v_provider_id uuid;
  v_credential_type_id uuid;
  v_status text;
  v_submitted_by uuid;
begin
  v_submission_id := private.credential_storage_submission_id(p_name);
  if v_submission_id is null then return false; end if;

  select provider_id, credential_type_id, status, submitted_by
    into v_provider_id, v_credential_type_id, v_status, v_submitted_by
  from public.credential_submissions
  where id = v_submission_id;

  if v_provider_id is null then return false; end if;

  return (
    v_provider_id = private.my_provider_id()
    and v_submitted_by = auth.uid()
    and v_status in ('draft', 'changes_requested')
    and split_part(p_name, '/', 1) = v_provider_id::text
    and private.provider_may_use_credential_type(v_provider_id, v_credential_type_id)
  )
  or private.can_manage_provider_credential(v_provider_id, v_credential_type_id);
end;
$$;

revoke execute on function private.credential_storage_submission_id(text) from public, anon;
revoke execute on function private.can_read_credential_storage_object(text) from public, anon;
revoke execute on function private.can_write_credential_storage_object(text) from public, anon;
grant execute on function private.credential_storage_submission_id(text) to authenticated;
grant execute on function private.can_read_credential_storage_object(text) to authenticated;
grant execute on function private.can_write_credential_storage_object(text) to authenticated;

drop policy if exists geaems_credential_documents_select on storage.objects;
drop policy if exists geaems_credential_documents_insert on storage.objects;
drop policy if exists geaems_credential_documents_delete on storage.objects;

create policy geaems_credential_documents_select on storage.objects
for select to authenticated
using (
  bucket_id = 'credential-documents'
  and (select private.can_read_credential_storage_object(name))
);

create policy geaems_credential_documents_insert on storage.objects
for insert to authenticated
with check (
  bucket_id = 'credential-documents'
  and (select private.can_write_credential_storage_object(name))
);

create policy geaems_credential_documents_delete on storage.objects
for delete to authenticated
using (
  bucket_id = 'credential-documents'
  and (select private.can_write_credential_storage_object(name))
);

-- -----------------------------------------------------------------------------
-- Validate and finalize a provider submission.
-- If verification is not required, the record is automatically promoted to the
-- current verified credential. Otherwise it enters the administrator queue.
-- -----------------------------------------------------------------------------

create or replace function public.finalize_credential_submission(p_submission_id uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_submission public.credential_submissions%rowtype;
  v_type public.credential_types%rowtype;
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

  if v_submission.provider_id is distinct from private.my_provider_id()
     or v_submission.submitted_by is distinct from auth.uid() then
    raise exception 'You may only submit credentials for your own provider record';
  end if;

  if v_submission.status not in ('draft', 'changes_requested') then
    raise exception 'Credential submission is not editable in status %', v_submission.status;
  end if;

  select * into v_type
  from public.credential_types
  where id = v_submission.credential_type_id;

  if not found or v_type.active = false then
    raise exception 'Credential type is inactive or unavailable';
  end if;

  if not private.provider_may_use_credential_type(v_submission.provider_id, v_submission.credential_type_id) then
    raise exception 'Credential type is not available to this provider';
  end if;

  if v_type.requires_number and nullif(btrim(v_submission.credential_number), '') is null then
    raise exception 'Credential number is required';
  end if;

  if v_type.requires_issue_date and v_submission.issue_date is null then
    raise exception 'Issue date is required';
  end if;

  if v_type.requires_expiration_date and v_submission.expiration_date is null then
    raise exception 'Expiration date is required';
  end if;

  if v_submission.issue_date is not null
     and v_submission.expiration_date is not null
     and v_submission.expiration_date < v_submission.issue_date then
    raise exception 'Expiration date cannot be before issue date';
  end if;

  if v_type.requires_document and not exists (
    select 1 from public.credential_documents cd
    where cd.submission_id = v_submission.id
  ) then
    raise exception 'A supporting credential document is required';
  end if;

  if exists (
    select 1 from public.credential_submissions cs
    where cs.provider_id = v_submission.provider_id
      and cs.credential_type_id = v_submission.credential_type_id
      and cs.id <> v_submission.id
      and cs.status in ('draft', 'pending', 'changes_requested')
  ) then
    raise exception 'Another open submission already exists for this credential';
  end if;

  if v_type.requires_verification then
    update public.credential_submissions
    set status = 'pending',
        submitted_at = now(),
        reviewed_by = null,
        reviewed_at = null,
        review_notes = null,
        updated_at = now()
    where id = v_submission.id;

    return 'pending';
  end if;

  -- Self-attested credential types can become current immediately.
  select id into v_old_credential_id
  from public.provider_credentials
  where provider_id = v_submission.provider_id
    and credential_type_id = v_submission.credential_type_id
    and is_current = true
    and verification_status = 'verified'
  for update;

  if v_old_credential_id is not null then
    update public.provider_credentials
    set is_current = false, updated_at = now()
    where id = v_old_credential_id;
  end if;

  insert into public.provider_credentials (
    provider_id, credential_type_id, credential_number, issue_date,
    expiration_date, verification_status, is_current, verified_by,
    verified_at, source, notes, supersedes_credential_id, created_by
  ) values (
    v_submission.provider_id, v_submission.credential_type_id,
    v_submission.credential_number, v_submission.issue_date,
    v_submission.expiration_date, 'verified', true, null,
    now(), 'provider_self_attested', v_submission.provider_notes,
    v_old_credential_id, v_submission.submitted_by
  ) returning id into v_new_credential_id;

  update public.credential_documents
  set provider_credential_id = v_new_credential_id,
      submission_id = null
  where submission_id = v_submission.id;

  update public.credential_submissions
  set status = 'approved',
      reviewed_at = now(),
      review_notes = 'Automatically accepted because this credential does not require verification.',
      resulting_credential_id = v_new_credential_id,
      updated_at = now()
  where id = v_submission.id;

  return 'approved';
end;
$$;

revoke execute on function public.finalize_credential_submission(uuid) from public, anon;
grant execute on function public.finalize_credential_submission(uuid) to authenticated;


-- Preserve provider notes when an administrator approves a submission.
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
    set is_current = false, updated_at = now()
    where id = v_old_credential_id;
  end if;

  insert into public.provider_credentials (
    provider_id, credential_type_id, credential_number, issue_date,
    expiration_date, verification_status, is_current, verified_by,
    verified_at, source, notes, supersedes_credential_id, created_by
  ) values (
    v_submission.provider_id, v_submission.credential_type_id,
    v_submission.credential_number, v_submission.issue_date,
    v_submission.expiration_date, 'verified', true,
    (select auth.uid()), now(), 'provider_submission',
    v_submission.provider_notes, v_old_credential_id, v_submission.submitted_by
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

commit;
