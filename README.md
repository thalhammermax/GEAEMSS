# GEAEMS Portal v0.4

Credential ownership and requirement scoping.

## Required Supabase step

Run **only** this new migration after migrations 001–004:

`supabase/migrations/005_credential_scope_and_requirements.sql`

Do not rerun 001–004 if they are already applied.

## Credential model

GEAEMS Portal now separates two concepts:

1. **Credential definition ownership**
   - **GEAEMS System credential** — created/owned by System Administration and visible system-wide.
   - **Agency credential** — created/owned by one participating agency and available only in that agency's credential context.

2. **Credential requirements**
   - **System requirement** — may be created only by a System Administrator and can apply to all active providers or one provider level.
   - **Agency requirement** — applies only to active providers affiliated with that agency and can apply to all provider levels or one provider level.

A System credential can also be required by an individual agency. This avoids duplicate definitions. For example, GEAEMS may define `PALS` once while one agency independently requires PALS for a provider group.

An agency-owned credential can only be required by its owning agency.

## Access rules

### System Administrator

- Create/edit/retire System credential definitions.
- Create/edit/retire agency credential definitions.
- Add System-wide requirements.
- Add or remove agency requirements.
- View compliance across the entire system.

### Agency Administrator with Credential permission

- View GEAEMS System credential definitions.
- Create/edit/retire credential definitions owned by an assigned agency.
- Add/remove requirements for an assigned agency.
- Use a GEAEMS System credential as an agency-specific requirement without duplicating it.
- Cannot edit a System credential definition.
- Cannot see another agency's private credential definitions or private credential records.

### Provider

- Still has self-service access only.
- Sees credential requirements that apply to the provider through GEAEMS or an active agency affiliation.
- Sees only their own credential records.

## Compliance behavior

A requirement with no provider level selected means **all active providers in that scope**.

Examples:

- `Illinois Paramedic License` → GEAEMS System → Paramedic = required for all active Paramedics system-wide.
- `BLS` → GEAEMS System → All provider levels = required for every active GEAEMS provider.
- `Driver Authorization` → Agency A → All provider levels = required for every active provider affiliated with Agency A.
- `PALS` → Agency B → Paramedic = a local requirement using the System-defined PALS credential.

The compliance view now excludes provider statuses configured not to count toward compliance and uses an agency-specific provider level when one is assigned on an agency affiliation.

## UI changes

- Credentials are split into **System credentials** and **Agency credentials**.
- Add Credential now asks who owns the credential.
- Credential detail pages now include a **Who is required to maintain this credential?** section.
- System credentials are read-only to Agency Administrators, but authorized Agency Administrators may add a local requirement.
- Provider and self-service profiles now show required credential compliance, including **Missing**, **Expired**, **Expiring soon**, and **Current**.

## Deployment

1. Run `005_credential_scope_and_requirements.sql` in Supabase SQL Editor.
2. Replace the GitHub repository contents with this version.
3. Push to your production branch and allow Netlify to rebuild.
4. Test first as a System Administrator.
5. Test with an Agency Administrator that has `Credentials` permission for one agency.
6. Test with a provider-only account affiliated with that agency.

No new Netlify environment variables are required.
