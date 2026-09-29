# GEAEMS Portal v0.3.6

Provider self-service access hardening.

## Required Supabase step

Run **only** this new migration after the prior migrations:

`supabase/migrations/004_provider_self_service_security.sql`

Do not rerun 001–003 if they are already applied.

## What changed

- Provider-level users now land on `/my-profile` rather than the system dashboard.
- Their sidebar contains only **My Profile**.
- A provider-level user who manually enters an administrative URL is redirected back to `/my-profile`.
- The self-service profile is read-only and shows only that user's linked provider record, current credentials, and agency affiliations.
- System Administrators and Agency Administrators keep the normal portal navigation.
- Agency access rows no longer grant privileges by themselves. The account must actually have the **Agency Administrator** role (or be a System Administrator).
- Removing the Agency Administrator role clears stored agency permission rows.
- The migration removes stale agency permissions from accounts that are no longer administrators.

## Deployment

1. Run migration `004_provider_self_service_security.sql` in Supabase SQL Editor.
2. Replace the GitHub repository contents with this version.
3. Push to the production branch and allow Netlify to rebuild.
4. Test with one provider-only login and one System Administrator login.

No new Netlify environment variables are required.
