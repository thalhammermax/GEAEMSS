'use client'

import { FormEvent, Suspense, useState } from 'react'
import { useRouter, useSearchParams } from 'next/navigation'
import { createClient } from '@/lib/supabase/client'
import { BrandLogo } from '@/components/brand-logo'

function LoginContent() {
  const router = useRouter()
  const searchParams = useSearchParams()
  const notice = searchParams.get('notice')
  const linkError = searchParams.get('error')
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(false)

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    setError('')
    setLoading(true)
    const supabase = createClient()
    const { error } = await supabase.auth.signInWithPassword({ email, password })
    setLoading(false)
    if (error) {
      setError(error.message)
      return
    }
    router.replace('/dashboard')
    router.refresh()
  }

  return <main className="login-page">
    <section className="login-panel">
      <BrandLogo size="large" />
      <div className="login-heading">
        <p className="eyebrow">Greater Elgin Area EMS System</p>
        <h1>GEAEMS Portal</h1>
        <p>Personnel, credential, vehicle licensing and inspection compliance.</p>
      </div>
      <form onSubmit={submit} className="login-form">
        <label>Email address<input type="email" autoComplete="email" required value={email} onChange={(e) => setEmail(e.target.value)} /></label>
        <label>Password<input type="password" autoComplete="current-password" required value={password} onChange={(e) => setPassword(e.target.value)} /></label>
        {notice && <div className="form-success">{notice}</div>}
        {linkError && <div className="form-error">{linkError}</div>}
        {error && <div className="form-error">{error}</div>}
        <button className="primary-button" disabled={loading}>{loading ? 'Signing in…' : 'Sign in'}</button>
      </form>
      <p className="login-footnote">Authorized GEAEMS users only.</p>
    </section>
    <aside className="login-art" aria-hidden="true"><div className="cross"><span/><span/></div><div className="login-art-copy">System readiness.<br/>One portal.</div></aside>
  </main>
}


function LoginFallback() {
  return <main className="login-page">
    <section className="login-panel">
      <BrandLogo size="large" />
      <div className="login-heading">
        <p className="eyebrow">Greater Elgin Area EMS System</p>
        <h1>GEAEMS Portal</h1>
        <p>Loading sign-in…</p>
      </div>
    </section>
    <aside className="login-art" aria-hidden="true"><div className="cross"><span/><span/></div><div className="login-art-copy">System readiness.<br/>One portal.</div></aside>
  </main>
}

export default function LoginPage() {
  return <Suspense fallback={<LoginFallback />}><LoginContent /></Suspense>
}
