# GEAEMS Portal

Initial live frontend for the Greater Elgin Area EMS System personnel and fleet compliance system.

Production target: `https://portal.geaemss.org`

## Included now

- Supabase email/password login
- Cookie-based Supabase SSR authentication for Next.js 16
- Row-Level-Security-aware data access (no service-role key in the browser)
- Protected portal shell
- System Admin dashboard with live counts
- Personnel registry view
- Credential configuration/summary view
- Fleet registry view
- Inspection history view
- Report catalog placeholder
- Administration summary
- Original initial Supabase migration for source control

Create/edit functions are intentionally disabled in this first UI milestone. The next phase is CRUD forms, provider detail pages, agency management, credential submission/verification, and vehicle/inspection workflows.

## Local run

The supplied archive contains a local `.env.local` using the publishable Supabase values supplied for this project. `.env.local` is ignored by Git.

```bash
npm install
npm run dev
```

Then open `http://localhost:3000` and sign in with the Supabase Auth user you created.

## Netlify deployment

1. Push this project to GitHub.
2. In Netlify, add a new project from that repository.
3. Netlify should detect Next.js automatically.
4. Add these environment variables in Netlify:
   - `NEXT_PUBLIC_SUPABASE_URL`
   - `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`
5. Deploy.
6. Add `portal.geaemss.org` as the custom domain in Netlify.
7. Point the DNS record Netlify requests from `geaemss.org` to the Netlify site.

## Supabase Auth URL configuration

Before production login flows are used, set the Supabase Authentication URL settings to include:

- Site URL: `https://portal.geaemss.org`
- Redirect URL: `https://portal.geaemss.org/**`
- During development also allow `http://localhost:3000/**`

## Security

This frontend uses only the Supabase publishable key. Never add a `service_role` key or secret API key to `NEXT_PUBLIC_*` variables or client-side code.
