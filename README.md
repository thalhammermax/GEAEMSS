# GEAEMS Portal v0.6.6

This release fixes Provider access to the Narcotics module and adds an administrative Narcotics History view.

## Before deployment

Run this migration in Supabase SQL Editor:

```text
supabase/migrations/014_provider_narcotics_access_and_history_privacy.sql
```

Run only `014`; migrations `001` through `013` should already be applied.

Then push the v0.6.6 project files to GitHub and allow Netlify to rebuild.

## Provider narcotics access

A Provider-only account can now access:

- **My Profile**
- **Narcotics**

Providers may start, save, resume, and electronically submit the daily count only for apparatus whose agency matches an active provider affiliation on their linked provider record.

Provider access to narcotics records follows least privilege:

- today's count/status for an actively affiliated agency is visible so providers can see whether the apparatus has already been counted;
- a provider can view historical counts they personally started or signed;
- the full agency narcotics history is not exposed to ordinary Provider accounts.

A System Inspector who is also linked to a provider record receives the same Narcotics access in addition to Inspections.

## Administrative history

System Administrators and Agency Administrators now have **Narcotics → History**.

The history page includes submitted daily-count logs with:

- count date and submission time;
- agency;
- apparatus;
- narcotics form;
- seal number;
- electronic signer;
- discrepancy status;
- a link to the immutable signed count detail.

Filters are available for agency, apparatus, date range, and discrepancy status.

System Administrators see system-wide history. Agency Administrators see only agencies assigned to them through Agency Administration access.
