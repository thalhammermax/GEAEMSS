# GEAEMS Portal v0.3.1

## v0.3.1 password-setup safety fix

This patch fixes a v0.3 bug where `/auth/setup-password` accepted any existing authenticated browser session and could therefore change the wrong user's password. Setup/reset links are now bound to the intended provider or Auth user, the identity is verified again immediately before the password change, and the recovery session is signed out after the password is saved.

**Deploy this patch before sending additional account setup or password reset emails.** No additional SQL migration is required beyond the v0.3 `003_user_account_security.sql` migration.


Greater Elgin Area EMS System personnel, credential, fleet, licensing and inspection compliance portal.

Production URL: `https://portal.geaemss.org`

## v0.3 adds

### Credential administration
- Create credential types
- Edit credential types
- Activate/deactivate credential types
- Permanently delete unused credential types
- If a credential type has requirements, provider history, or submissions, a delete request safely deactivates it instead of destroying compliance history
- Configure credential category, renewal interval, required fields, verification, documents, and warning thresholds

### User management
- Administration → User Management
- View Supabase Auth users from inside the portal
- Link provider records to portal accounts
- Provider email address is the login username
- Send provider account setup invitations
- Send password setup/reset emails later
- Enable/disable portal access
- Manage Provider, Agency Administrator, and System Administrator roles
- Assign Agency Administrator permissions by agency for Personnel, Credentials, and Fleet
- Prevent a System Administrator from disabling their own account or removing their own System Administrator role

### Provider creation
- New optional checkbox: **Email this provider a portal account setup link**
- The checkbox is OFF by default
- If left off, the provider record is created with no login account
- The account can be invited later from Administration → User Management
- If selected, the provider must have an email address and that email becomes the login username

### Account setup
- Invited users are sent to `/auth/setup-password`
- The user sets their own password; administrators do not set or see it
- Disabled profiles are blocked from administrative RLS access as well as from portal pages

v0.2 features remain: agency management, personnel registry, multi-agency affiliations, fleet registry, configurable built-in fields, custom fields, GEAEMS branding, and the original compliance schema.

## IMPORTANT: run migration 003

You have already run migrations 001 and 002.

Before using the user enable/disable controls, run the complete contents of:

`supabase/migrations/003_user_account_security.sql`

in **Supabase → SQL Editor**.

Migration 003 makes `profiles.active` authoritative for System Administrator and Agency Administrator RLS access.

## Required Netlify environment variables

The existing browser-safe variables remain:

- `NEXT_PUBLIC_SUPABASE_URL`
- `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`

For v0.3 User Management, add this **server-only** variable in Netlify:

- `SUPABASE_SECRET_KEY`

Use the Supabase **secret** key (`sb_secret_...`) from Project Settings → API Keys. Do not prefix it with `NEXT_PUBLIC_`, do not commit it to GitHub, and do not paste it into client-side code.

For projects still using the legacy key, the build also accepts:

- `SUPABASE_SERVICE_ROLE_KEY`

Do not configure both unless you have a reason to; prefer `SUPABASE_SECRET_KEY` for new projects.

Recommended production variable:

- `NEXT_PUBLIC_SITE_URL=https://portal.geaemss.org`

The code defaults to that production URL if the variable is absent.

After adding/changing Netlify variables, use **Clear cache and deploy site**.

## Supabase Auth URL configuration

Keep:

- Site URL: `https://portal.geaemss.org`
- Redirect URL: `https://portal.geaemss.org/**`
- Development: `http://localhost:3000/**`

The wildcard production redirect covers the new `/auth/setup-password` route.

## Invitation behavior

Supabase's invitation API is called only from server-side code. When the optional provider invitation is used:

1. Provider record is created.
2. Supabase Auth creates/invites the user at the provider email address.
3. The Auth user is linked to the provider through `public.profiles`.
4. The user receives the Provider role.
5. The email link sends them to the password setup page.

If the provider record succeeds but the email invitation fails, the provider is retained and the portal shows the invitation error. An administrator can retry from User Management.

## Existing provider records

You do **not** need to create login accounts for all providers. This is intentional. Import all personnel first if desired, then invite only the users who need portal access.

## Email sending limits

Supabase's built-in email service is suitable for development and low-volume individual invitations, but it has sending restrictions. Before a large rollout to hundreds of providers, configure custom SMTP (for example Resend or another organizational mail service) in Supabase Auth.

## Development

```bash
npm install
npm run dev
```

Type check:

```bash
npm run typecheck
```

Production build:

```bash
npm run build
```

## Security

The Supabase publishable key is browser-safe and is used by the normal portal client. The Supabase secret/service-role key bypasses Row Level Security and is used only in server-side User Management functions. Never expose it in browser code, public environment variables, or GitHub.


## v0.3.2 Netlify build fix

This patch wraps the `/login` and `/auth/setup-password` components that use Next.js `useSearchParams()` in React `Suspense` boundaries. This satisfies the Next.js 16 production prerender requirement and preserves the v0.3.1 password-setup identity safeguards.

No new Supabase migration is required for v0.3.2.
