'use client'

import { FormEvent, useEffect, useState } from 'react'
import { useRouter } from 'next/navigation'
import { createClient } from '@/lib/supabase/client'
import { BrandLogo } from '@/components/brand-logo'

export default function SetupPasswordPage() {
  const router = useRouter()
  const [password, setPassword] = useState('')
  const [confirm, setConfirm] = useState('')
  const [ready, setReady] = useState(false)
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(false)

  useEffect(() => {
    const supabase = createClient()
    let mounted = true
    async function check() {
      // createBrowserClient processes invite/recovery URL data in the browser.
      await new Promise((resolve) => setTimeout(resolve, 150))
      const { data } = await supabase.auth.getSession()
      if (!mounted) return
      if (!data.session) setError('This setup link is invalid or has expired. Ask a System Administrator to send a new password setup email.')
      else setReady(true)
    }
    check()
    const { data: listener } = supabase.auth.onAuthStateChange((_event, session) => {
      if (mounted && session) { setReady(true); setError('') }
    })
    return () => { mounted = false; listener.subscription.unsubscribe() }
  }, [])

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    setError('')
    if (password.length < 8) { setError('Password must be at least 8 characters.'); return }
    if (password !== confirm) { setError('Passwords do not match.'); return }
    setLoading(true)
    const supabase = createClient()
    const { error } = await supabase.auth.updateUser({ password })
    setLoading(false)
    if (error) { setError(error.message); return }
    router.replace('/dashboard')
    router.refresh()
  }

  return <main className="login-page">
    <section className="login-panel">
      <BrandLogo size="large" />
      <div className="login-heading"><p className="eyebrow">Greater Elgin Area EMS System</p><h1>Set your password</h1><p>Create the password you will use with your email address to sign in to the GEAEMS Portal.</p></div>
      <form onSubmit={submit} className="login-form">
        <label>New password<input type="password" autoComplete="new-password" required minLength={8} value={password} onChange={(e) => setPassword(e.target.value)} disabled={!ready}/></label>
        <label>Confirm password<input type="password" autoComplete="new-password" required minLength={8} value={confirm} onChange={(e) => setConfirm(e.target.value)} disabled={!ready}/></label>
        {error && <div className="form-error">{error}</div>}
        <button className="primary-button" disabled={!ready || loading}>{loading ? 'Saving…' : ready ? 'Set password' : 'Validating link…'}</button>
      </form>
    </section>
    <aside className="login-art" aria-hidden="true"><div className="cross"><span/><span/></div><div className="login-art-copy">One identity.<br/>One system.</div></aside>
  </main>
}
