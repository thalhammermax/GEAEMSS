# GEAEMS Portal v0.6.2

Production URL: `https://portal.geaemss.org`

v0.6.2 keeps the v0.6.1 inspection-form editor/draft privacy changes and revises **Narcotics Management** in three important ways:

1. daily narcotics forms are assigned by **vehicle type**, not by agency default;
2. incomplete daily narcotics counts are surfaced at the top of the Dashboard; and
3. every narcotics count records a **Seal Number**, with a mandatory explanation when the seal changes from the immediately preceding submitted count for that apparatus.

## Vehicle-type narcotics forms

Go to:

**Narcotics → Forms & settings**

System Administrators can assign a GEAEMS System narcotics form to each active vehicle type. Every apparatus automatically uses the form assigned to its current vehicle type.

Examples:

- `GEA ALS Ambulance` → `GEAEMS Standard ALS Narcotics`
- `GEA ALS Non-Transport` → `GEAEMS ALS Non-Transport Narcotics`
- `GEA Critical Care Transport` → `GEAEMS Critical Care Narcotics`

There is **no agency default narcotics form** in the v0.6.2 workflow, and the vehicle record no longer exposes a per-apparatus template selector. Existing v0.6 agency-default and vehicle-override assignments are cleared by migration 010, but all previously submitted narcotics counts retain the exact `template_id` snapshot they used.

The database columns from the original v0.6 implementation are retained for migration compatibility but are marked deprecated and are ignored by the current count workflow.

## Seal Number workflow

Every daily narcotics count now includes:

- **Seal Number**
- **Previous submitted Seal Number** (when one exists)
- **Reason seal changed** (required only when the current seal differs from the previous submitted seal)

The count page shows the previous seal to the provider. As soon as the provider enters a different current seal, the UI displays and requires the reason field.

The database independently enforces the same rule at final submission, so bypassing the browser cannot submit an unexplained seal change.

The signed SHA-256 submission payload now includes the current seal, prior seal, and seal-change reason.

Historical submitted counts created before v0.6.2 may not have a seal number. The first v0.6.2 submission for that apparatus establishes the baseline; subsequent changes require an explanation.

## Dashboard incomplete-count alert

The main Dashboard now displays a high-priority narcotics alert **above Personnel and Fleet** whenever a visible count-required apparatus does not have a submitted count for its agency's current local date.

A count remains incomplete when it is:

- not started;
- saved as a draft but not signed/submitted; or
- unable to start because its vehicle type has no narcotics form assigned.

The alert is authorization-scoped automatically by Supabase RLS:

- System Administrators see the system-wide apparatus they are authorized to view;
- Agency Administrators see their authorized agencies;
- providers continue to use the Narcotics module directly and do not gain administrative Dashboard access.

The automated Agency Admin email report also distinguishes **No form configured for vehicle type**, **Draft not submitted**, and **Not started**.

## Provider count authorization

Providers may perform and electronically sign a narcotics count only when their login is linked to an active provider record that is actively affiliated with the apparatus agency for the count date.

System/Agency administrative status alone does not authorize a signature.

## Daily report settings

Agency settings still control:

- whether Narcotics Management is enabled for that agency;
- agency time zone;
- daily incomplete-count report hour;
- whether the incomplete-count report is emailed; and
- the electronic-signature attestation text.

They no longer contain a default narcotics form selector.

The scheduled Netlify function remains:

`netlify/functions/narcotics-daily-report.mjs`

and continues to require:

```text
NEXT_PUBLIC_SUPABASE_URL
SUPABASE_SECRET_KEY
RESEND_API_KEY
```

Optional sender override:

```text
NARCOTICS_REPORT_FROM=GEAEMS Portal <no-reply@auth.geaemss.org>
```

## Deploying v0.6.2

Your project should already have migrations `001` through `009` applied.

Run only:

```text
supabase/migrations/010_narcotics_vehicle_type_forms_and_seals.sql
```

in **Supabase → SQL Editor**. Do not rerun migrations 001–009.

Then push the v0.6.2 application files to GitHub and allow Netlify to rebuild.

### Required configuration after migration 010

Because v0.6.2 intentionally removes agency-default/vehicle-override form selection, configure the vehicle types before expecting providers to submit counts:

1. Open **Narcotics → Forms & settings** as a System Administrator.
2. Create/edit the GEAEMS System narcotics count forms you need.
3. Under **Daily narcotics form assignment**, assign the appropriate form to each ALS/critical-care vehicle type.
4. Open **Fleet** and confirm the apparatus has the correct vehicle type and that daily narcotics counts are enabled.
5. Perform a test count and enter a Seal Number.
6. Submit a second test-day count with a different seal and confirm a change reason is required.
7. Confirm an incomplete count appears at the top of the Dashboard until it is signed and submitted.

## Inspection behavior retained from v0.6.1

- System Administrators can create versioned editable inspection-form drafts and publish new versions.
- Published inspection versions remain immutable for historical integrity.
- System inspection drafts are visible only to **System Inspectors** and **System Administrators**.
- Agency Administrators do not receive in-progress System inspection drafts through normal queries or direct record access.
