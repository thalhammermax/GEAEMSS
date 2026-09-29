# GEAEMS Portal v0.9.0

Production portal: `https://portal.geaemss.org`

v0.9 adds the **Continuing Education (CE) Tracking** module while retaining Personnel, Credentials, Fleet, Inspections, Narcotics, Reports, Administration, and the v0.8 credential self-service workflow.

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
