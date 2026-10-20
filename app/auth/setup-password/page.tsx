import { createClient } from '@/lib/supabase/server'
import { validateSetupIdentity } from '@/lib/setup-identity'
import { BrandLogo } from '@/components/brand-logo'
import { SetupPasswordForm } from './setup-password-form'

type Props = { searchParams: Promise<{ uid?: string; provider?: string }> }

export default async function SetupPasswordPage({ searchParams }: Props) {
  const { uid, provider } = await searchParams
  // The invite/recovery session was created server-side by /auth/confirm
  // (token_hash flow), so the identity can be validated here without any
  // browser-side Supabase traffic.
  const supabase = await createClient()
  const identity = await validateSetupIdentity(supabase, uid ?? null, provider ?? null)

  return <main className="login-page">
    <section className="login-panel">
      <BrandLogo size="large" />
      <div className="login-heading">
        <p className="eyebrow">Greater Elgin Area EMS System</p>
        <h1>Set your password</h1>
        <p>Create the password you will use with your email address to sign in to the GEAEMS Portal.</p>
        {identity.email && <p><strong>Account:</strong> {identity.email}</p>}
      </div>
      <SetupPasswordForm uid={uid ?? ''} provider={provider ?? ''} ready={!identity.error} initialError={identity.error} />
    </section>
    <aside className="login-art" aria-hidden="true"><div className="cross"><span/><span/></div><div className="login-art-copy">One identity.<br/>One system.</div></aside>
  </main>
}
