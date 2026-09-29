# GEAEMS Portal v0.3.5

## Password setup identity fix

This patch changes `/auth/confirm` so the password setup page is bound to the **user ID actually verified by Supabase**, rather than depending on `RedirectTo` to preserve a `uid` or `provider` query parameter. This fixes the “password setup link is missing its account identity” error for both invitation and recovery emails.

No Supabase SQL migration is required. Deploy the code, then send a **new** invite/reset email. Previously issued or already-used auth links should not be reused.

---

# GEAEMS Portal v0.3.4

Hotfix for invite/password-reset session handoff.

## What changed

`/auth/confirm` now creates the Supabase SSR client inside the Route Handler and writes the invite/recovery session cookies directly onto the redirect response that sends the user to `/auth/setup-password`.

This fixes a failure mode where `verifyOtp()` succeeded but the following password-setup page did not receive the authenticated session and displayed:

> This setup link is invalid, has expired, or has not finished signing you in.

The identity checks introduced in v0.3.1 remain in place. The password page still refuses to update a password unless the session user matches the user/provider encoded into the setup link.

## Deployment

No SQL migration is required.

Replace the repository contents with v0.3.4 and deploy through Netlify.

After deployment, send a **new** invitation or password setup email. Do not reuse a previously clicked/expired link because Supabase email tokens are one-time credentials.

## Supabase email template links

Reset Password:

```html
<a href="{{ .SiteURL }}/auth/confirm?token_hash={{ .TokenHash }}&type=recovery&next={{ .RedirectTo }}">
  Reset password
</a>
```

Invite User:

```html
<a href="{{ .SiteURL }}/auth/confirm?token_hash={{ .TokenHash }}&type=invite&next={{ .RedirectTo }}">
  Set up GEAEMS Portal account
</a>
```

Supabase Authentication URL Configuration should include:

- Site URL: `https://portal.geaemss.org`
- Redirect URL: `https://portal.geaemss.org/**`
