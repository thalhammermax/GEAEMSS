# GEAEMS Portal v0.6.3

This point release adds the missing **Agency Inspection Form creation workflow**.

## Before deploying

Run only:

`supabase/migrations/011_agency_inspection_form_creation.sql`

Migrations 001–010 should already be applied.

## Agency Administrator workflow

An Agency Administrator must have **Fleet** permission for the agency.

1. Open **Inspections**.
2. Choose **Manage forms**.
3. Choose **New agency form**.
4. Select an agency the user has Fleet permission for.
5. Select the vehicle type.
6. Enter the form name and optional description.
7. The portal creates **version 1 as a draft** and opens the form editor.
8. Add sections/items and publish the version when ready.

Agency-owned forms do not replace GEAEMS System forms. They are separate inspection checklists and can only be performed for vehicles in the owning agency.

For deterministic form selection, the portal permits one active agency inspection form per **agency + vehicle type**. To change the checklist, edit/version the existing form instead of creating duplicates.

## Permissions

- **System Administrator:** can create agency forms for any active agency.
- **Agency Administrator + Fleet permission:** can create and edit agency forms for authorized agencies.
- **System Inspector:** does not create agency-owned forms by virtue of the System Inspector role.
- **Provider:** no inspection form administration access.

A generic **Agency Vehicle Inspection** inspection type is added by migration 011 so agency inspections are labeled separately from the official GEAEMS System Vehicle Equipment Inspection in history/reporting.
