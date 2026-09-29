# GEAEMS Portal v0.6

Production URL: `https://portal.geaemss.org`

v0.6 adds a full **Narcotics Management** module to the existing personnel, credential, fleet, and digital inspection portal.

## Daily narcotics counts

- ALS and critical-care apparatus are automatically marked as requiring a daily count when they use the GEAEMS ALS / Critical Care vehicle types.
- Other vehicles may be manually enabled from their Fleet record.
- Providers can perform a count **only when their portal login is linked to an active provider affiliation with that vehicle's agency**.
- Agency Administrator or System Administrator status by itself does not authorize an electronic count signature; the signer must also be an affiliated provider.
- Each apparatus has one count record per calendar day.
- Counts can be saved as drafts and resumed later.
- Submitted counts are locked from editing.
- Any actual quantity that differs from the template's expected quantity is automatically flagged as a discrepancy.

## Electronic signature

Submission requires:

1. every active template item to have an actual count;
2. the provider to type their name;
3. the provider to accept the agency's electronic-signature attestation.

The database records the authenticated user, linked provider, typed signature, timestamp, attestation, and a SHA-256 signature hash generated from the signed count snapshot.

## Templates

Go to:

**Narcotics → Templates & settings**

System Administrators can create GEAEMS System templates. Agency Administrators with **Narcotics** permission can create templates owned by their agency.

Each template item supports:

- medication / controlled substance name;
- concentration;
- dosage form;
- optional controlled-substance schedule label;
- expected quantity;
- unit label;
- sort order.

An agency can select a default template. A Fleet record can optionally override that template for an individual apparatus.

## Agency permissions

Migration 008 adds two agency-access settings under User Management:

- **Narcotics** — allows that Agency Administrator to manage their agency's narcotics templates/settings.
- **Narcotics email report** — includes that Agency Administrator on the automated incomplete-count report.

Existing Agency Administrator access rows default to receiving the report.

## Automated incomplete-count report

The repository includes:

`netlify/functions/narcotics-daily-report.mjs`

It is a Netlify Scheduled Function that runs hourly. For each enabled agency, once the configured local report hour has passed, it checks every active apparatus requiring a narcotics count. If one or more do not have a **submitted** count for that local date, the function emails the Agency Administrators who have **Narcotics email report** enabled.

A draft counts as incomplete until it is electronically signed and submitted.

The function records successful or no-action daily runs in `narcotics_report_history` so an agency does not receive duplicate daily alerts.

### Netlify environment variable required

Add this server-side environment variable in Netlify:

```text
RESEND_API_KEY=re_...
```

You can use the same Resend API key that you configured as the SMTP password for Supabase Auth. Do **not** place it in GitHub or prefix it with `NEXT_PUBLIC_`.

Optional sender override:

```text
NARCOTICS_REPORT_FROM=GEAEMS Portal <no-reply@auth.geaemss.org>
```

The scheduled function also uses the existing:

```text
NEXT_PUBLIC_SUPABASE_URL
SUPABASE_SECRET_KEY
```

Ensure those variables and `RESEND_API_KEY` are available to Netlify Functions at runtime.

## Deploying v0.6

Your project should already have migrations `001` through `007` applied.

Run only:

```text
supabase/migrations/008_narcotics_management.sql
```

in **Supabase → SQL Editor**.

Then replace/push the v0.6 application files to GitHub and allow Netlify to rebuild.

After deployment:

1. Open **Narcotics → Templates & settings**.
2. Create at least one count template and add the medications/controlled substances to it.
3. Assign a default template to each participating agency.
4. Verify each ALS apparatus under **Fleet**. GEAEMS ALS/CC vehicle types are automatically count-required.
5. In **Administration → User Management**, confirm which Agency Administrators should receive narcotics reports.
6. Add `RESEND_API_KEY` to Netlify.
7. In Netlify **Functions**, confirm `narcotics-daily-report` appears with a **Scheduled** badge. You can use **Run now** to test it without waiting for the schedule.

## Existing v0.5 inspection functionality

Digital system inspections and the System Inspector role from migrations 006 and 007 remain unchanged.
