import type { Metadata } from 'next'
import Link from 'next/link'
import { createClient } from '@/lib/supabase/server'
import { getCredentialAdminContext } from '@/lib/credential-access'
import { PageHeader } from '@/components/page-header'
import { setCredentialTypeActive } from './actions'

export const metadata: Metadata = { title: 'Credentials' }
type Props = { searchParams: Promise<{ error?: string; notice?: string }> }

function canManageAgency(agencies:any[], id:string|null) {
  return !!id && agencies.some((a:any) => a.id === id)
}

export default async function CredentialsPage({ searchParams }: Props) {
  const { error: queryError, notice } = await searchParams
  const supabase = await createClient()
  const context = await getCredentialAdminContext(supabase)
  const [{ data: types, error }, { count: currentCount }, { count: requirementCount }, { count: pendingCount }] = await Promise.all([
    supabase.from('credential_types').select('*, agencies(name, short_name)').order('scope_type').order('category').order('name'),
    supabase.from('provider_credentials').select('*', { count: 'exact', head: true }).eq('is_current', true).eq('verification_status', 'verified'),
    supabase.from('credential_requirements').select('*', { count: 'exact', head: true }).eq('required', true),
    supabase.from('credential_submissions').select('*', { count: 'exact', head: true }).eq('status', 'pending'),
  ])

  const rows = (types ?? []) as any[]
  const systemRows = rows.filter((r:any) => r.scope_type === 'system')
  const agencyRows = rows.filter((r:any) => r.scope_type === 'agency')
  const canCreate = context.isSystemAdmin || context.manageableAgencies.length > 0

  const renderTable = (items:any[]) => items.length === 0 ? <div className="empty-state compact"><strong>No credentials in this section</strong></div> : <table><thead><tr><th>Credential</th><th>Owner</th><th>Category</th><th>Renewal</th><th>Status</th><th></th></tr></thead><tbody>{items.map((r:any) => {
    const editable = context.isSystemAdmin || (r.scope_type === 'agency' && canManageAgency(context.manageableAgencies, r.agency_id))
    return <tr key={r.id}><td><strong>{r.name}</strong><div className="muted-code">{r.code}</div></td><td>{r.scope_type === 'system' ? <span className="pill green">GEAEMS System</span> : <><strong>{r.agencies?.short_name || r.agencies?.name || 'Agency'}</strong><div className="muted-code">Agency credential</div></>}</td><td>{r.category}</td><td>{r.renewal_months ? `${r.renewal_months} months` : 'Variable'}</td><td><span className={`pill ${r.active ? 'green' : ''}`}>{r.active ? 'Active' : 'Inactive'}</span></td><td className="table-action"><div className="inline-actions"><Link href={`/credentials/${r.id}/edit`}>{editable ? 'Manage' : 'View'}</Link>{editable && <form action={setCredentialTypeActive}><input type="hidden" name="id" value={r.id}/><input type="hidden" name="active" value={r.active ? 'false' : 'true'}/><button className="text-button" type="submit">{r.active ? 'Deactivate' : 'Activate'}</button></form>}</div></td></tr>
  })}</tbody></table>

  return <>
    <PageHeader title="Credentials" description="GEAEMS System credentials apply across the system. Agencies may also maintain local credential definitions and requirements." action={<div className="inline-actions"><Link className="secondary-button button-link" href="/credentials/submissions">Review submissions{(pendingCount ?? 0) > 0 ? ` (${pendingCount})` : ''}</Link>{canCreate && <Link className="primary-button button-link" href="/credentials/new">Add credential</Link>}</div>} />
    {notice && <div className="banner success"><div><strong>Credential updated</strong><span>{notice}</span></div></div>}
    {queryError && <div className="banner danger"><div><strong>Credential action failed</strong><span>{queryError}</span></div></div>}
    <div className="summary-strip"><div><span>System credentials</span><strong>{systemRows.length}</strong></div><div><span>Agency credentials visible to you</span><strong>{agencyRows.length}</strong></div><div><span>Current credential records</span><strong>{currentCount ?? 0}</strong></div><div><span>Pending verification</span><strong>{pendingCount ?? 0}</strong></div><div><span>Active requirements</span><strong>{requirementCount ?? 0}</strong></div></div>

    <section className="section-block"><div className="section-title"><div><span>GEAEMS</span><h2>System credentials</h2></div><div className="section-badge">{systemRows.length}</div></div><div className="table-card">{error ? <div className="empty-state danger-text">{error.message}</div> : renderTable(systemRows)}</div></section>

    <section className="section-block"><div className="section-title"><div><span>Local requirements</span><h2>Agency credentials</h2></div><div className="section-badge">{agencyRows.length}</div></div><div className="table-card">{renderTable(agencyRows)}</div></section>
  </>
}
