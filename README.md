# GEAEMS Portal v0.8.0

Production portal: `https://portal.geaemss.org`

v0.8 adds the provider credential self-service and verification workflow. It retains the Reporting, Personnel, Fleet, Inspections, Narcotics, Administration, user-management, and security functionality from v0.7.

## New in v0.8

### Provider credential self-service
Providers can now manage credentials from **My Profile**.

The compliance list shows an action for each applicable requirement:

- **Add credential** when a required credential is missing
- **Renew** when a verified credential already exists
- **Continue** for a saved draft or a submission returned for corrections
- **View submission** while a credential is awaiting verification

Providers may also use **My Profile -> Add credential** to submit an active GEAEMS System credential or an agency-owned credential available through one of their active agency affiliations.

### Safe submission lifecycle
Credential submissions now support:

```text
Draft
  -> Pending verification
  -> Approved
  -> Rejected
  -> Changes requested -> provider edits -> Pending verification
```

A provider may save an incomplete draft without affecting the verified credential already on file. The current verified credential remains authoritative until a replacement is approved.

Credential definitions control whether the provider must enter:

- credential number
- issue date
- expiration date
- supporting document
- administrator verification

If a credential definition has **Verification required = Off**, a valid provider submission is automatically accepted into the verified credential history. If verification is required, the submission enters the administrator review queue.

### Supporting credential documents
Migration 016 creates a private Supabase Storage bucket named:

```text
credential-documents
```

Providers can attach PDF, JPG, PNG, or WebP files up to 10 MB. Storage access is protected by Supabase RLS. Providers can only upload documents to their own editable credential submissions. Administrators can only read documents for credential records within their current authorization scope.

### Credential verification queue
Administrators now have:

**Credentials -> Review submissions**

The queue shows provider-submitted credentials that are pending or have changes requested.

The review screen shows:

- provider identity
- submitted credential number/dates
- provider notes
- supporting document(s)
- the currently verified credential, if one exists

Authorized administrators can:

- **Approve credential**
- **Request changes** with instructions to the provider
- **Reject** with a required reason

Approval creates a new current verified credential, supersedes the prior current record, preserves historical credential data, and moves the uploaded document metadata to the verified credential record.

Existing credential-scope authorization remains in effect: System Administrators can review all accessible submissions, while Agency Administrators are limited by their current credential-management permissions and agency scope.

## Database migration

If migrations `001` through `015` are already installed, run only:

```text
supabase/migrations/016_provider_credential_self_service.sql
```

Do not rerun prior migrations.

Migration 016:

- adds credential-submission drafts and provider notes
- creates the private `credential-documents` Storage bucket
- adds Storage RLS policies
- validates required fields/documents before final submission
- adds automatic acceptance for credential definitions that do not require verification
- preserves provider notes when an administrator approves a credential

## Deploy

1. Run `supabase/migrations/016_provider_credential_self_service.sql` in Supabase SQL Editor.
2. Replace the GitHub repository contents with this version.
3. Push/commit to the production branch.
4. Let Netlify build and deploy.
5. Sign in as a Provider and open **My Profile** to test an Add Credential submission.
6. Sign in as a System Administrator and open **Credentials -> Review submissions** to approve the test credential.

No new Netlify environment variables are required for v0.8.
