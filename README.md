# GEAEMS Portal v0.3.3

This release fixes Supabase SSR invite/password-recovery links so the intended user is authenticated before the password setup screen is shown.

## Important: Supabase email template changes are REQUIRED

The app now includes `GET /auth/confirm`, which verifies Supabase `TokenHash` values server-side and establishes the correct user's session cookie before redirecting to `/auth/setup-password`.

In **Supabase Dashboard → Authentication → Emails → Templates**, update these two templates.

### Reset Password template

The important part is that the button/link href is:

```html
<a href="{{ .SiteURL }}/auth/confirm?token_hash={{ .TokenHash }}&type=recovery&next={{ .RedirectTo }}">
  Reset password
</a>
```

You may keep your own surrounding HTML/branding.

### Invite User template

The important part is that the button/link href is:

```html
<a href="{{ .SiteURL }}/auth/confirm?token_hash={{ .TokenHash }}&type=invite&next={{ .RedirectTo }}">
  Set up GEAEMS Portal account
</a>
```

You may keep your own surrounding HTML/branding.

## Supabase URL configuration

Under **Authentication → URL Configuration** confirm:

```text
Site URL:
https://portal.geaemss.org
```

and an allowed redirect URL such as:

```text
https://portal.geaemss.org/**
```

## Why this change is needed

GEAEMS administrators initiate invitations and recovery emails for other users from the server. A server-side `TokenHash` verification route is therefore safer and more reliable than assuming the recipient has an existing browser-side PKCE verifier.

The confirm route only permits `invite` and `recovery` token types and only redirects to `/auth/setup-password` on the same portal origin.

The password setup page still re-verifies the signed-in user's expected user/provider identity immediately before changing the password.

## Deployment

No new database migration is required.

Replace the repo contents with this build and let Netlify redeploy.

After deployment, update the two Supabase email templates above **before sending another test invitation/reset**. Old emails generated from the previous template should not be used for testing this flow.
