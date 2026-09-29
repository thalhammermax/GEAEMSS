'use client'

import { FormEvent, useCallback, useEffect, useState } from 'react'
import { useRouter, useSearchParams } from 'next/navigation'
import { createClient } from '@/lib/supabase/client'
import { BrandLogo } from '@/components/brand-logo'

const WRONG_USER_MESSAGE = 'This password setup link belongs to a different portal user. Sign out of the portal or open the email link in a private/incognito window, then try again.'

export default function SetupPasswordPage() {
  const router = useRouter()
  const searchParams = useSearchParams()
  const expectedUserId = searchParams.get('uid')
  const expectedProviderId = searchParams.get('provider')

  const [password, setPassword] = useState('')
  const [confirm, setConfirm] = useState('')
  const [ready, setReady] = useState(false)
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(false)
  const [accountEmail, setAccountEmail] = useState('')

  const validateIdentity = useCallback(async () => {
    setReady(false)

    if (!expectedUserId && !expectedProviderId) {
      setError('This password setup link is missing its account identity. Ask a System Administrator to send a new setup email.')
      return false
    }

    const supabase = createClient()
    const { data: { user }, error: userError } = await supabase.auth.getUser()

    if (userError || !user) {
      setError('This setup link is invalid, has expired, or has not finished signing you in. Ask a System Administrator to send a new password setup email.')
      return false
    }

    if (expectedUserId && user.id !== expectedUserId) {
      setError(WRONG_USER_MESSAGE)
      return false
    }

    if (expectedProviderId) {
      const { data: profile, error: profileError } = await supabase
        .from('profiles')
        .select('provider_id')
        .eq('id', user.id)
        .maybeSingle()

      if (profileError || profile?.provider_id !== expectedProviderId) {
        setError(WRONG_USER_MESSAGE)
        return false
      }
    }

    setAccountEmail(user.email ?? '')
    setError('')
    setReady(true)
    return true
  }, [expectedProviderId, expectedUserId])

  useEffect(() => {
    const supabase = createClient()
    let mounted = true

    const validate = async () => {
      // Give the auth client a moment to process an invite/recovery URL before
      // evaluating the resulting identity. Never trust a pre-existing session.
      await new Promise((resolve) => setTimeout(resolve, 250))
      if (mounted) await validateIdentity()
    }

    validate()

    const { data: listener } = supabase.auth.onAuthStateChange((event) => {
      if (!mounted) return
      if (event === 'PASSWORD_RECOVERY' || event === 'SIGNED_IN' || event === 'TOKEN_REFRESHED') {
        setTimeout(() => { if (mounted) void validateIdentity() }, 0)
      }
    })

    return () => {
      mounted = false
      listener.subscription.unsubscribe()
    }
  }, [validateIdentity])

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    setError('')

    if (password.length < 8) {
      setError('Password must be at least 8 characters.')
      return
    }
    if (password !== confirm) {
      setError('Passwords do not match.')
      return
    }

    setLoading(true)

    // Re-check the identity immediately before the destructive auth change.
    const identityIsCorrect = await validateIdentity()
    if (!identityIsCorrect) {
      setLoading(false)
      return
    }

    const supabase = createClient()
    const { error: updateError } = await supabase.auth.updateUser({ password })
    if (updateError) {
      setLoading(false)
      setError(updateError.message)
      return
    }

    // End the recovery/invite session. The user must perform a normal login
    // with the password they just chose, which also avoids leaving a shared
    // browser signed in as the invited account.
    await supabase.auth.signOut()
    setLoading(false)
    router.replace('/login?notice=Password%20saved.%20Sign%20in%20with%20your%20email%20and%20new%20password.')
    router.refresh()
  }

  return <main className="login-page">
    <section className="login-panel">
      <BrandLogo size="large" />
      <div className="login-heading">
        <p className="eyebrow">Greater Elgin Area EMS System</p>
        <h1>Set your password</h1>
        <p>Create the password you will use with your email address to sign in to the GEAEMS Portal.</p>
        {accountEmail && <p><strong>Account:</strong> {accountEmail}</p>}
      </div>
      <form onSubmit={submit} className="login-form">
        <label>New password<input type="password" autoComplete="new-password" required minLength={8} value={password} onChange={(e) => setPassword(e.target.value)} disabled={!ready || loading}/></label>
        <label>Confirm password<input type="password" autoComplete="new-password" required minLength={8} value={confirm} onChange={(e) => setConfirm(e.target.value)} disabled={!ready || loading}/></label>
        {error && <div className="form-error">{error}</div>}
        <button className="primary-button" disabled={!ready || loading}>{loading ? 'Saving…' : ready ? 'Set password' : 'Validating link…'}</button>
      </form>
    </section>
    <aside className="login-art" aria-hidden="true"><div className="cross"><span/><span/></div><div className="login-art-copy">One identity.<br/>One system.</div></aside>
  </main>
}
