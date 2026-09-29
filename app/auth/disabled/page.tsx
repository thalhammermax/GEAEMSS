'use client'

import { useState } from 'react'
import { useRouter } from 'next/navigation'
import { BrandLogo } from '@/components/brand-logo'
import { createClient } from '@/lib/supabase/client'

export default function DisabledPage() {
  const router = useRouter()
  const [loading, setLoading] = useState(false)
  async function signOut() {
    setLoading(true)
    const supabase = createClient()
    await supabase.auth.signOut()
    router.replace('/login')
    router.refresh()
  }
  return <main className="login-page"><section className="login-panel"><BrandLogo size="large"/><div className="login-heading"><p className="eyebrow">Greater Elgin Area EMS System</p><h1>Portal access unavailable</h1><p>Your GEAEMS Portal account is disabled or has not been provisioned. Contact System Administration if you believe you should have access.</p></div><button className="primary-button" onClick={signOut} disabled={loading}>{loading ? 'Signing out…' : 'Return to sign in'}</button></section><aside className="login-art" aria-hidden="true"><div className="cross"><span/><span/></div></aside></main>
}
