import type { Metadata } from 'next'
import { createClient } from '@/lib/supabase/server'
import { PageHeader } from '@/components/page-header'

export const metadata: Metadata = { title: 'Credentials' }

export default async function CredentialsPage() {
  const supabase = await createClient()
  const [{ data: types, error }, { count: currentCount }, { count: requirementCount }] = await Promise.all([
    supabase.from('credential_types').select('*').order('category').order('name'),
    supabase.from('provider_credentials').select('*', { count: 'exact', head: true }).eq('is_current', true).eq('verification_status', 'verified'),
    supabase.from('credential_requirements').select('*', { count: 'exact', head: true }).eq('required', true),
  ])
  return <><PageHeader title="Credentials" description="Configure credential types, requirements, renewals and verification." />
    <div className="summary-strip"><div><span>Credential types</span><strong>{types?.length ?? 0}</strong></div><div><span>Current records</span><strong>{currentCount ?? 0}</strong></div><div><span>Active requirements</span><strong>{requirementCount ?? 0}</strong></div></div>
    <div className="table-card">{error ? <div className="empty-state danger-text">{error.message}</div> : <table><thead><tr><th>Credential</th><th>Category</th><th>Renewal</th><th>Verification</th><th>Status</th></tr></thead><tbody>{(types ?? []).map((r: any) => <tr key={r.id}><td><strong>{r.name}</strong><div className="muted-code">{r.code}</div></td><td>{r.category}</td><td>{r.renewal_months ? `${r.renewal_months} months` : 'Variable'}</td><td>{r.requires_verification ? 'Required' : 'Not required'}</td><td><span className={`pill ${r.active ? 'green' : ''}`}>{r.active ? 'Active' : 'Inactive'}</span></td></tr>)}</tbody></table>}</div></>
}
