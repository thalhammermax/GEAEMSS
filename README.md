# GEAEMS Portal v0.2

Greater Elgin Area EMS System personnel, credential, fleet, licensing and inspection compliance portal.

Production URL: `https://portal.geaemss.org`

## v0.2 includes

- Supabase email/password authentication with Next.js SSR
- RLS-aware System Admin / Agency Admin / Provider data access foundation
- System dashboard with live database counts
- Agency create/edit/inactivate workflow
- Personnel registry with search and agency/level/status filters
- Provider create/edit pages
- Multiple agency affiliations per provider
- Provider profile with credential summary
- Fleet registry with search and filters
- Vehicle create/edit/inactivate workflow
- Configurable built-in fields for Personnel, Agencies and Vehicles
- Custom fields for Personnel, Agencies and Vehicles
  - Text
  - Long text
  - Number
  - Date
  - Yes/No
  - Email
  - Phone
  - URL
  - Dropdown
  - Multi-select
- Custom field values protected by the same RLS model as their parent records
- Audit logging for field-definition and custom-value changes
- Official GEAEMS logo hooks for portal branding, favicon and installable-app icon

Credential-entry/renewal workflows, automated alerts, report export, vehicle licensing entry and inspection entry are subsequent builds. The underlying database tables for those modules are already present from migration 001.

## IMPORTANT: run migration 002

Migration `001_initial_schema.sql` has already been run for this project.

Before deploying this version, run the complete contents of:

`supabase/migrations/002_record_fields_and_personnel_admin.sql`

in **Supabase → SQL Editor**.

Migration 002 adds configurable/custom record fields and the controlled provider-creation RPC used by agency personnel administrators.

## Official GEAEMS logo

The app expects the official logo at:

`public/geaems-logo.png`

The supplied logo should be saved to that path in GitHub. It is then used automatically for:

- Login screen
- Portal sidebar
- Browser favicon
- Apple touch icon
- Web-app manifest icons

The UI contains a small fallback mark so a missing logo file will not prevent the portal from loading.

## Netlify environment variables

Configure these in Netlify rather than committing `.env.local`:

- `NEXT_PUBLIC_SUPABASE_URL`
- `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`

Then redeploy.

## Supabase Auth URL configuration

- Site URL: `https://portal.geaemss.org`
- Redirect URL: `https://portal.geaemss.org/**`
- Development: `http://localhost:3000/**`

## Development

```bash
npm install
npm run dev
```

Type check:

```bash
npm run typecheck
```

Production build:

```bash
npm run build
```

## Security

Only the Supabase publishable key belongs in the browser application. Never expose the Supabase secret/service-role key in GitHub, Netlify public variables, or client-side code.

## Branding assets
The GEAEMS logo is included in this build. The portal uses it for the login screen and sidebar, and generated square derivatives are included for the favicon, Apple touch icon, and installable web-app manifest. No manual logo copy step is required.
