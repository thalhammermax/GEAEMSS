# GEAEMS Portal v0.5.1

GEAEMS System personnel, credential, fleet, and digital vehicle inspection portal.

Production URL: `https://portal.geaemss.org`

## v0.5 — Digital Inspections

v0.5 turns the Inspections module into an inspection workflow rather than a history-only screen.

### Included inspection profiles

The supplied `gea-idph-ems-comparison-matrix.xlsx` is included under `docs/` and is seeded into versioned digital forms for:

- GEA BLS Non-Transport — 81 applicable checklist items
- GEA BLS Ambulance — 94 applicable checklist items
- GEA ALS Non-Transport — 118 applicable checklist items
- GEA ALS Ambulance — 135 applicable checklist items
- GEA Critical Care Transport — 144 applicable checklist items

The source matrix contains 147 unique line items in 11 sections. Items marked `N/A` for a vehicle profile are omitted from that vehicle's inspection form. Exact requirement text from the matrix (quantity, sets, sizes, medication totals, `Required`, etc.) is displayed next to each checklist item.

### Inspector workflow

1. Open **Inspections**.
2. Select **Start inspection**.
3. Select a vehicle.
4. The portal loads the published form that matches the vehicle's type.
5. For each applicable item, mark **Compliant** or **Deficient**, with optional observed/count and notes.
6. Use **Mark section compliant** to speed up a section.
7. Save an incomplete inspection as a draft and resume it later.
8. Submit the inspection when every required line item has a disposition.
9. Failed line items automatically become vehicle deficiencies.
10. Submitted inspections are locked for normal agency editing and remain historical records against the exact form version used.

### Vehicle types

Migration 006 adds the five specific matrix vehicle types while leaving existing generic fleet types intact. Vehicles that need digital matrix inspections should use one of these five types. A generic vehicle type will show that no inspection form is assigned.

### Versioning

Inspection forms are versioned. Completed inspections reference the exact form version and exact line-item definitions used at the time of inspection. Future edits to a template will therefore not rewrite historic inspections.

The schema supports both System-owned and Agency-owned inspection templates, although v0.5 ships the supplied matrix as GEAEMS System templates. A visual template editor can be added later without redesigning completed-inspection storage.

## Deploying v0.5

Your database should already have migrations `001` through `005` applied.

Run only:

```text
supabase/migrations/006_digital_vehicle_inspections.sql
```

in **Supabase → SQL Editor**.

Then push the v0.5 application files to GitHub and allow Netlify to rebuild.

No new Netlify environment variables are required.

## Existing environment variables

```text
NEXT_PUBLIC_SUPABASE_URL
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY
SUPABASE_SECRET_KEY
NEXT_PUBLIC_SITE_URL=https://portal.geaemss.org
```

Never commit the Supabase secret key to GitHub.


## v0.5.1 patch

Fixed a Next.js/TypeScript build failure on the Start Inspection page caused by Supabase relationship joins being inferred as arrays. No database migration changes are required beyond migration 006 from v0.5.
