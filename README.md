# GEAEMS Portal v0.7.0

Production portal: `https://portal.geaemss.org`

v0.7 turns Reports into a working reporting platform. It retains the Personnel, Credentials, Fleet, Inspections, Narcotics, Administration, user-management, and security functionality from v0.6.6.

## New in v0.7

### Standard reports
The Reports page now includes runnable presets for:

- System Personnel Roster
- Agency Personnel Roster
- Credential Compliance
- Credential Expiration
- Missing Required Credentials
- Expired Credentials
- Pending Credential Verification
- Provider Credential History
- Credential Type Census
- Fleet Roster
- Vehicle License Expiration
- Upcoming / Overdue Inspections
- Inspection History
- Open Inspection Deficiencies
- Narcotics Count History
- System Compliance Summary
- Agency Compliance Summary

Every standard report uses current Supabase/RLS permissions. Agency Administrators therefore only receive data available within their agency-administration scope.

### Custom Report Builder
`Reports -> Build custom report`

Administrators can choose a data source, select columns, add multiple filters, sort, group, preview, and save a reusable report.

Available data sources include Personnel, Agencies, provider credential compliance/current/history/submissions/census, Fleet, vehicle licensing, inspection compliance/history/deficiencies, Narcotics history, and agency compliance summary.

Enabled custom Personnel, Agency, and Vehicle fields created under Administration -> Field Configuration automatically become report fields. No code update is needed when a new custom field is added.

### CSV export
Standard and saved reports have a Download CSV action. CSV files include all matching rows available to the current administrator.

### Scheduled email reports
Any saved custom report can optionally be scheduled:

- Daily
- Weekly
- Monthly
- Local delivery hour
- Time zone
- Up to 25 email recipients
- Table in email
- CSV attachment
- Table + CSV attachment

The Netlify `report-scheduler` function runs hourly and sends each scheduled report once for its due period.

Critically, scheduled report security is evaluated again at delivery time. The report owner's current active status, role, and agency access are re-read. If an Agency Administrator loses an agency assignment, future scheduled deliveries no longer include that agency. If the owner no longer has a System Administrator or Agency Administrator role, the scheduled run is skipped.

Delivery history is stored with the saved report, including status, date, recipient count, row count, and any error.

## Database migration

If migrations `001` through `014` are already installed, run only:

```text
supabase/migrations/015_reports_and_scheduling.sql
```

Do not rerun prior migrations.

## Netlify environment variables

The existing variables remain required:

```text
NEXT_PUBLIC_SUPABASE_URL
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY
SUPABASE_SECRET_KEY
NEXT_PUBLIC_SITE_URL=https://portal.geaemss.org
RESEND_API_KEY
```

The report scheduler reuses the same Resend API key already used by the Narcotics module.

Optional sender override:

```text
REPORTS_FROM=GEAEMS Portal <no-reply@auth.geaemss.org>
```

If `REPORTS_FROM` is omitted, that same sender is used by default.

## Deploy

1. Run migration `015_reports_and_scheduling.sql` in Supabase SQL Editor.
2. Replace the GitHub repository contents with this version.
3. Push/commit to the production branch.
4. Let Netlify build and deploy.
5. In Netlify -> Functions, confirm `report-scheduler` appears as a scheduled function.
6. Open Reports in the portal and create a saved report.

The scheduler uses `@hourly`. The report's configured local delivery hour and time zone determine whether a report is due on a given hourly run.

## Email-volume note

Scheduled reports share the Resend account with other portal emails. On Resend's free tier, keep the account's daily message limit in mind when creating many scheduled reports or large recipient lists.
