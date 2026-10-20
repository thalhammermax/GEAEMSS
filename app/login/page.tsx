import type { Metadata } from 'next'
import { BrandLogo } from '@/components/brand-logo'
import { LoginForm } from './login-form'

export const metadata: Metadata = { title: 'Sign in' }

type Props = { searchParams: Promise<{ notice?: string; error?: string }> }

export default async function LoginPage({ searchParams }: Props) {
  const { notice, error } = await searchParams
  return <main className="login-page">
    <section className="login-panel">
      <BrandLogo size="large" />
      <div className="login-heading">
        <p className="eyebrow">Greater Elgin Area EMS System</p>
        <h1>GEAEMS Portal</h1>
        <p>Personnel, credential, vehicle licensing and inspection compliance.</p>
      </div>
      <LoginForm notice={notice} linkError={error} />
      <p className="login-footnote">Authorized GEAEMS users only.</p>
    </section>
    <aside className="login-art" aria-hidden="true"><div className="cross"><span/><span/></div><div className="login-art-copy">System readiness.<br/>One portal.</div></aside>
  </main>
}
