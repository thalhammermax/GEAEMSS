import type { Metadata } from 'next'
import Link from 'next/link'
import { createClient } from '@/lib/supabase/server'
import { PageHeader } from '@/components/page-header'
import { setCredentialTypeActive } from './actions'

export const metadata: Metadata = { title: 'Credentials' }
type Props = { searchParams: Promise<{ error?: string; notice?: string }> }

export default async function CredentialsPage({ searchParams }: Props) {
  const { error: queryError, notice } = await searchParams
  const supabase = await createClient()
  const [{ data: types, error }, { count: currentCount }, { count: requirementCount }] = await Promise.all([
    supabase.from('credential_types').select('*').order('category').order('name'),
    supabase.from('provider_credentials').select('*', { count: 'exact', head: true }).eq('is_current', true).eq('verification_status', 'verified'),
    supabase.from('credential_requirements').select('*', { count: 'exact', head: true }).eq('required', true),
  ])
  return <>
    <PageHeader title="Credentials" description="Create and maintain credential definitions. Provider requirements and individual credential records remain separate." action={<Link className="primary-button button-link" href="/credentials/new">Add credential</Link>} />
    {notice && <div className="banner success"><div><strong>Credential updated</strong><span>{notice}</span></div></div>}
    {queryError && <div className="banner danger"><div><strong>Credential action failed</strong><span>{queryError}</span></div></div>}
    <div className="summary-strip"><div><span>Credential types</span><strong>{types?.length ?? 0}</strong></div><div><span>Current records</span><strong>{currentCount ?? 0}</strong></div><div><span>Active requirements</span><strong>{requirementCount ?? 0}</strong></div></div>
    <div className="table-card">{error ? <div className="empty-state danger-text">{error.message}</div> : <table><thead><tr><th>Credential</th><th>Category</th><th>Renewal</th><th>Verification</th><th>Status</th><th></th></tr></thead><tbody>{(types ?? []).map((r: any) => <tr key={r.id}><td><strong>{r.name}</strong><div className="muted-code">{r.code}</div></td><td>{r.category}</td><td>{r.renewal_months ? `${r.renewal_months} months` : 'Variable'}</td><td>{r.requires_verification ? 'Required' : 'Not required'}</td><td><span className={`pill ${r.active ? 'green' : ''}`}>{r.active ? 'Active' : 'Inactive'}</span></td><td className="table-action"><div className="inline-actions"><Link href={`/credentials/${r.id}/edit`}>Edit</Link><form action={setCredentialTypeActive}><input type="hidden" name="id" value={r.id}/><input type="hidden" name="active" value={r.active ? 'false' : 'true'}/><button className="text-button" type="submit">{r.active ? 'Deactivate' : 'Activate'}</button></form></div></td></tr>)}</tbody></table>}</div>
  </>
}
