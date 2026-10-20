# GEAEMS Portal v0.11.0

v0.10 adds staged **module rollout controls** and **multi-module reporting**. The initial production configuration enables Fleet, Inspections, and Reports while Personnel, Credentials, CE Tracking, and Narcotics remain disabled until GEAEMS is ready to roll them out.

Production portal: `https://portal.geaemss.org`


## New in v0.11.0 — Performance & network-accessibility release

This release changes no features. It makes every page load faster and makes the portal reachable from restrictive networks (hospital Wi-Fi/LAN) by ensuring the **browser only ever talks to `portal.geaemss.org`**.

### What changed

**Authentication plumbing (biggest speed win)**

- The proxy (middleware) now verifies the session token locally with `getClaims()` instead of calling the Supabase Auth server with `getUser()` on every request. (Requires the project's JWT signing keys to be asymmetric — see *Deploy* below.)
- Roles, profile, agency access and module rollout state are loaded with **one** database call (`get_session_context()`, migration 023) and forwarded from the proxy to the page render. Previously the proxy, the portal layout and most pages each re-queried `user_roles` / `profiles` / `system_module_settings` separately (6–9 round trips per page).
- `createClient()` and `getModuleStates()` are memoized per request, so helpers that call them repeatedly no longer repeat work.
- `lib/session.ts` provides `requireSession()` / `requireUser()`; pages use these instead of `supabase.auth.getUser()`.

**Database (migration 023)**

- `is_system_admin()` and `has_agency_access()` do one indexed lookup instead of two to three.
- Administrator **fast-path RLS policies** (`_fast_system_admin_read`) on every data table. They are evaluated once per statement, so System Administrators no longer pay for the per-row `can_view_*()` helper chain. Agency administrators get an equivalent hashed fast path on `agencies` and `vehicles`.
- `dashboard_summary()` computes all dashboard counts in one call (was 17 separate count queries).
- Supporting indexes for the hottest list screens.

**Server-side sign-in / sign-out / password setup**

- Sign-in, sign-out and invite/recovery password setup now run as Next.js server actions. The browser never loads the Supabase JavaScript client or contacts `*.supabase.co` for these flows.
- Instant route-level loading skeleton (`app/(portal)/loading.tsx`) so navigation never appears frozen.

The only remaining browser-to-Supabase traffic is the provider credential **document upload** in the Credentials module (currently disabled). See *Network accessibility* below before enabling that module.

### Database migration

If migrations `001` through `022` are already installed, run only:

```text
supabase/migrations/023_performance_session_and_dashboard.sql
```

The application tolerates the migration not being applied yet (it falls back to the old query pattern), but it will not be faster until it is.

### Deploy

1. Run migration 023 in the Supabase SQL Editor.
2. Supabase Dashboard → **Project Settings → JWT Keys** → if the project still uses the legacy HS256 shared secret, choose **Migrate to asymmetric JWT signing** (zero-downtime; existing sessions keep working). Without this step `getClaims()` silently falls back to a network call and the proxy is no faster than before.
3. Supabase Dashboard → **Authentication → Email Templates** → change the *Invite user* and *Reset password* templates so the link goes to the portal instead of Supabase (required for the server-side password setup, and so the link works on networks that block `supabase.co`):

   ```html
   <a href="{{ .SiteURL }}/auth/confirm?token_hash={{ .TokenHash }}&type=invite&next={{ .RedirectTo }}">Set up your GEAEMS Portal password</a>
   ```

   (use `type=recovery` in the reset-password template). Confirm **Authentication → URL Configuration → Site URL** is `https://portal.geaemss.org` and that `https://portal.geaemss.org/auth/confirm` and `https://portal.geaemss.org/auth/setup-password` are listed under *Redirect URLs*.
4. Commit and deploy from GitHub. No new environment variables are required.
5. Smoke test: sign in, open Dashboard / Fleet / Inspections, sign out, and send one password-setup email to a test account.

### Network accessibility (hospital networks)

Hospital web filters typically block in one of two places, and both must be clear:

| Symptom | Cause | Fix |
| --- | --- | --- |
| `portal.geaemss.org` itself will not load (block page or timeout) | The domain is uncategorized / "newly registered" in the hospital's web filter (Zscaler, Palo Alto, Cisco Umbrella, Fortinet, etc.) | Ask hospital IT to allow-list `portal.geaemss.org`, and submit the domain for categorization as *Business / Healthcare* with the filter vendor. |
| Login page loads but **Sign in** hangs or fails | The browser was calling `<project>.supabase.co` directly | Fixed in v0.11.0 — sign-in now goes through the portal's own server. |
| Invite / reset-password email links fail | Default Supabase email links point at `<project>.supabase.co` | Update the email templates as described in *Deploy* step 3. |

If the Credentials module is enabled later, provider document uploads still go browser → Supabase Storage. Options at that point: (a) add a **Supabase custom domain** (e.g. `api.geaemss.org`, Pro-plan add-on) so that traffic stays under the allow-listed `geaemss.org` domain, or (b) route uploads through a server action (limited to ~4–6 MB per file on Netlify/Vercel).

### Hosting

Netlify + Supabase is a reasonable production stack and is **not** the cause of the hospital block. If page loads still feel slow after this release, the remaining cost is serverless cold starts; the lowest-friction upgrade is **Vercel** (native Next.js host, Fluid Compute reduces cold starts, same GitHub workflow, same environment variables). Whichever host is used, keep the custom domain and the `/auth/confirm` email-link setup above.

## New in v0.10.3 — Narcotics requirement checkbox fix

The Fleet vehicle setting **Require a signed daily narcotics count for this apparatus** is now truly operator-controlled.

The original Narcotics migration contained a database trigger that automatically forced this field back to `true` for GEA ALS Non-Transport, GEA ALS Ambulance, and GEA Critical Care Transport vehicle types. That trigger overrode the value submitted by the Fleet form, which is why unchecking the box appeared to save and then immediately returned as checked.

Migration 021 removes that forced behavior. When the Narcotics module is enabled, the Fleet checkbox can now be checked or unchecked normally for any vehicle type.

When the Narcotics module is disabled:

- the Narcotics Management section is hidden from Add/Edit Vehicle screens
- vehicle saves force `narcotics_count_required = false`
- migration 021 clears existing stale daily-count requirements while Narcotics is disabled
- no ALS or critical-care vehicle is automatically re-enabled for Narcotics solely because of its vehicle type

When Narcotics is rolled out later, enable the module and explicitly select which apparatus should require daily signed counts.

### Database migration

If migrations `001` through `020` are already installed, run only:

```text
supabase/migrations/021_narcotics_requirement_control.sql
```

Do not edit or rerun migration 008; migration 021 intentionally supersedes its old forced-ALS trigger.

## New in v0.10.2 — Agency archiving for production rollout

Agencies now use the existing `agencies.active` field as a true archive workflow, matching the vehicle archive behavior.

### Current vs archived agencies

**Administration → Agencies** now opens to **Current agencies** by default. System administrators can:

- archive an individual agency
- select multiple current agencies and choose **Archive selected**
- review archived agencies separately
- bulk restore archived agencies
- open an archived agency without deleting any underlying history

Archiving an agency does **not** modify or delete its providers, affiliations, vehicles, inspections, licenses, deficiencies, custom fields, or audit history.

### Parent-agency behavior

Vehicles keep their own active/archive state when an agency is archived. While the parent agency is archived, its otherwise-active vehicles are treated as unavailable for production. Restoring the agency automatically makes those still-active vehicles available again, while vehicles that were individually archived remain archived.

Archived agencies and their vehicles are excluded from:

- Current Agencies
- Current Fleet
- the Start Inspection vehicle picker
- the active Inspections list and deficiency summary
- vehicle licensing and inspection compliance views
- dashboard fleet/compliance counts
- standard Fleet, Inspection, Vehicle + Inspection, and Agency reports
- scheduled Narcotics incomplete-count reminders

Historical vehicle and inspection records remain accessible through the archived agency/vehicle records, including inspection PDF exports.

### Database migration

If migrations `001` through `019` are already installed, run only:

```text
supabase/migrations/020_agency_archive_compliance.sql
```

Migration 020 updates the vehicle-license and vehicle-inspection compliance views so active vehicles under an archived agency do not produce production compliance exceptions.

## New in v0.10.1 — Vehicle archiving for production rollout

Fleet records now use the existing vehicle `active` flag as a true archive workflow.

### Current fleet vs archived vehicles

**Fleet** now opens to the **Current fleet** by default. Archived vehicles are hidden from normal production use and can be reviewed separately with **Archived vehicles** or the Fleet view filter.

Fleet administrators can:

- archive one vehicle from its Vehicle record
- select multiple current vehicles and choose **Archive selected**
- review archived vehicles separately
- select multiple archived vehicles and choose **Restore selected**
- open an archived vehicle and retain its complete inspection history

Archiving does not delete the vehicle, inspections, licenses, deficiencies, custom fields, or audit history.

### Production isolation

Archived vehicles are excluded from:

- the normal Current Fleet list
- the Start Inspection vehicle picker
- the active Inspections list and open-deficiency summary
- Fleet and Vehicle + Inspection operational reports
- Inspection History and Inspection Deficiency standard reports
- vehicle compliance dashboards and compliance views
- Narcotics operational reporting for active apparatus

Completed inspection records remain available from the archived Vehicle record and can still be opened or exported as PDF.

This release uses the existing `vehicles.active` database field, so **no new Supabase migration is required**.

## New in v0.10 — Staged module rollout & multi-module reports

### Module rollout controls

System Administrators now have **Administration → Module Controls**.

The following modules can be enabled or disabled independently:

- Personnel
- Credentials
- CE Tracking
- Fleet
- Inspections
- Narcotics
- Reports

The v0.10 migration initializes the staged rollout requested for production:

- **Fleet — enabled**
- **Inspections — enabled**
- **Reports — enabled**
- Personnel — disabled
- Credentials — disabled
- CE Tracking — disabled
- Narcotics — disabled

Dashboard and Administration remain core portal services and cannot be disabled.

Disabling a module does not delete its records. It hides the module from normal navigation, blocks non-System Administrators from its routes, and pauses module-specific scheduled activity. System Administrators retain maintenance access so future modules can be prepared before rollout.

Dependencies are enforced:

- Inspections requires Fleet.
- Narcotics requires Fleet.
- Credentials requires Personnel.
- CE Tracking requires Personnel.

### Multi-module report builder

Reports remain enabled during the initial rollout.

The report builder now supports safe **combined datasets** instead of forcing every report to come from only one module.

**Vehicle + Inspection Operations** creates one row per vehicle and combines fields from:

- Fleet
- Inspection compliance
- Latest completed inspection
- Open/critical inspection deficiencies
- Narcotics summary fields automatically appear later when Narcotics is enabled
- Vehicle custom fields

This allows reports such as:

- every apparatus with its latest inspection result and next due date
- vehicle roster with open/critical deficiency counts
- fleet grouped by agency with inspection compliance status
- apparatus with overdue/missing inspections

**Provider + Credential + CE Overview** creates one row per provider and combines:

- Personnel
- Credential compliance summary fields when Credentials is enabled
- CE totals/history summary fields when CE Tracking is enabled
- Provider custom fields

The combined datasets intentionally aggregate one-to-many relationships so the report builder does not create accidental cartesian duplicates.

Existing single-module report datasets remain available when their required modules are enabled.

Scheduled reports re-check both the report owner's current access and the current module rollout settings before each delivery. If a required module has been disabled, the scheduled run is skipped rather than exposing disabled-module data.

### Database migration

If migrations `001` through `018` are already installed, run only:

```text
supabase/migrations/019_module_rollout_and_multimodule_reports.sql
```

Migration 019 also updates the saved-report data-source constraint to include the CE report sources introduced in v0.9 and the new combined report datasets.

## New in v0.9.2 — Editable inspection PDF template

System Administrators now have **Inspections → PDF template**.

The editor controls the system-wide presentation used whenever an inspection is exported to PDF, including:

- organization name and report title
- accent color and section-heading background color
- customizable Summary, Notes, Checklist, and Deficiencies headings
- custom footer text
- toggles for the vehicle detail line and result badge
- form version, submission timestamp, next-due date, and inspection ID visibility
- overall notes, full checklist, requirement text, observed values, and checklist notes
- deficiencies and corrective-action notes
- PDF generation timestamp, page numbers, and draft watermark

The editor includes both an on-screen approximation and a **Preview sample PDF** action that generates the real PDF renderer with sample inspection data.

Template changes affect future exports immediately. They do not modify the inspection record or the historical checklist version attached to a completed inspection.

### Database migration

If migrations `001` through `017` are already installed, run only:

```text
supabase/migrations/018_inspection_pdf_template.sql
```

Do not rerun prior migrations.

## New in v0.9.1 — Inspection records & PDF export

### Completed inspections on the Vehicle record
Each Fleet → Vehicle record now includes a **Completed inspection forms** section. Submitted inspections stay attached to the apparatus and display:

- inspection date
- inspection/form name and historical form version
- final result
- inspector
- next-due date
- links to open the inspection or download its PDF

This is intentionally historical: if an inspection form is later edited and republished, the Vehicle record still points to the exact form version that was used for the completed inspection.

### Inspection PDF export
Every inspection that the signed-in user is authorized to view can be downloaded as a PDF from either the inspection detail screen, the inspection history list, or the Vehicle record.

The PDF includes the GEAEMS report header, vehicle and agency details, inspection metadata, the complete digital checklist and responses, notes, deficiencies/corrective actions, pagination, and a generation timestamp. Draft inspection PDFs are visibly watermarked **DRAFT**. Legacy inspection records export the information that exists on the legacy record.

This release adds the `pdf-lib` runtime dependency and requires **no new Supabase migration**.

## New in v0.9 — CE Tracking

### CE roles
System Administration can now assign two CE-specific roles:

- **CE Coordinator** — creates CE classes, schedules dates/locations, reviews external CE certificates, manages any CE roster, and assigns instructors.
- **CE Instructor** — manages attendance, manual roster entry, and end-of-session completion codes for sessions to which the instructor is assigned.

System Administrators have CE Coordinator authority automatically.

A CE Coordinator or CE Instructor does not need a linked provider record just to administer CE. If the account is also linked to a provider, it retains normal provider self-service access as well.

### Classes with multiple dates and locations
A CE class is created once with its title, course code, category, description, and default CE hours. The CE Coordinator can then add any number of scheduled sessions beneath that class.

Each session stores its own:

- date and start/end time
- time zone
- location name and address/room/link
- optional capacity
- optional CE-hour override
- self check-in setting
- check-in opening window
- completion-code validity window
- instructor assignments
- session notes and status

This allows one class to be offered repeatedly on different dates and at different locations while keeping a separate attendance roster for every offering.

### Provider electronic check-in
Providers see upcoming CE offerings under **CE Tracking**.

During the configured check-in window they can select **Check in**. The database validates the session time, self-check-in setting, provider linkage, and optional capacity before creating the attendance record.

Checking in does **not** award CE credit by itself.

### Random end-of-session completion code
At the end of class, a CE Coordinator or assigned CE Instructor selects **Generate & release code**.

The portal generates a random six-character code. The secret value is stored separately from the provider-readable session record so providers cannot retrieve it from normal session queries.

A provider who already checked in enters the code in the portal. A successful match changes the attendance record to **Completed** and awards the session CE hours. The verification timestamp and method are retained for auditing.

### Manual roster entry
CE Coordinators and assigned CE Instructors can enter attendance manually from a paper roster or make a roster correction.

The roster screen provides a system-provider directory, optional notes, and the ability to mark the provider complete and award the class credit. Electronic and manual entries appear together on the same authoritative session roster.

### Electronic roster generation
Every CE session has a roster that can be:

- viewed in the portal
- downloaded as CSV
- printed

The generated roster includes provider name, System ID, agency, attendance status, check-in/verification times, verification method, entry source, CE hours, and notes.

### External / online CE certificates
Provider self-service now supports CE completed outside the GEAEMS electronic attendance workflow.

Examples include online mandated reporter training or another outside CE course that provides a completion certificate.

Providers enter:

- training/course title
- sponsor/provider
- category
- completion date
- CE hours (0 is allowed for tracked training that does not award hours)
- notes
- completion certificate

Certificates are stored in a private Supabase Storage bucket named:

```text
ce-certificates
```

Accepted formats are PDF, JPG, PNG, and WebP up to 10 MB.

External CE remains **Pending** until a CE Coordinator or System Administrator approves or rejects it. Approved CE becomes part of the provider's transcript.

Standing licenses/certifications such as BLS, ACLS, PALS, or a state license should still be tracked in the **Credentials** module rather than submitted as CE.

### Provider CE transcript
**CE Tracking → My transcript** combines:

- verified instructor-led GEAEMS attendance
- approved external/online CE certificates

Providers can view total hours, category totals, print the transcript, or download it as CSV.

### Reports integration
The v0.7 custom report engine now includes CE data sources:

- **CE Completion History**
- **CE Session Attendance**

Standard CE Completion History and CE Session Attendance reports are also included. Because they use the existing report engine, they can be customized, filtered, saved, exported, and scheduled for emailed delivery.

Agency Administrator report scope remains limited to providers within the administrator's currently authorized agencies. System Administrators can report system-wide.

## Database migration

If migrations `001` through `016` are already installed, run only:

```text
supabase/migrations/017_ce_tracking.sql
```

Do not rerun prior migrations.

Migration 017:

- adds `ce_coordinator` and `ce_instructor` roles
- creates CE course, session, instructor-assignment, attendance, and external-submission tables
- creates secure CE completion-code handling
- creates the private `ce-certificates` Storage bucket and RLS policies
- adds provider self check-in and code-verification RPCs
- adds manual roster and limited provider/instructor directory RPCs
- adds external CE review functions
- extends report-safe CE visibility to current agency administrative scope

## Deploy

1. Run `supabase/migrations/017_ce_tracking.sql` in the Supabase SQL Editor.
2. Commit/deploy this version from GitHub.
3. Let Netlify build and deploy.
4. In **Administration → Users**, assign at least one **CE Coordinator** and **CE Instructor** as appropriate.
5. Create a CE class under **CE Tracking → Manage classes** and add two test sessions with different dates/locations.
6. Assign a CE Instructor to a session.
7. Test provider check-in, instructor code release, provider completion verification, and roster export.
8. Test an external CE certificate upload and approval.

No new Netlify environment variables are required for v0.9.
