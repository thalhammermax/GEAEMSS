# GEAEMS Portal v0.6.4

This point release ties **Agency Administrator access directly to provider agency affiliations**.

## Before deploying

Run only:

`supabase/migrations/012_agency_admin_affiliation_enforcement.sql`

Migrations 001–011 should already be applied.

## Agency Administrator assignment rules

A user can only be offered the **Agency Administrator** role when the account is linked to a provider record that has at least one active affiliation with an active agency.

On the user-management page:

- If the provider has no active agency affiliations, **Agency Administrator does not appear as a role option at all**.
- If the provider is affiliated with Elgin FD and Bartlett FD, only Elgin FD and Bartlett FD appear in **Agency administration access**.
- Every other agency is omitted from the page entirely; it is not shown disabled and cannot be selected.
- Ending an affiliation automatically removes that user's agency-admin access for that agency.
- If all active affiliations are removed, the Agency Administrator role itself is removed automatically.
- Relinking a portal account to another provider or deactivating an agency also cleans up invalid agency-admin assignments.

The database contains matching validation triggers as a safety net, but the normal user interface does not present invalid choices.

## Existing functionality

All v0.6.3 functionality remains, including agency inspection form creation, inspection form editing/versioning, draft-system-inspection privacy, Narcotics Management, System Inspector access, credentials, personnel, fleet, and user management.
