import type { Metadata } from 'next'
import Link from 'next/link'
import { createClient } from '@/lib/supabase/server'
import { PageHeader } from '@/components/page-header'
import { formatDate, titleCase } from '@/lib/format'

export const metadata: Metadata = { title: 'Credential Verification' }
type Props = { searchParams: Promise<{ notice?: string; error?: string; status?: string }> }

export default async function CredentialSubmissionsPage({ searchParams }: Props) {
  const qs = await searchParams
  const supabase = await createClient()
  const statusFilter = qs.status || 'open'
  let query = supabase.from('credential_submissions').select('id, provider_id, credential_type_id, credential_number, expiration_date, status, submitted_at, reviewed_at, providers(first_name, last_name, provider_number), credential_types(name, scope_type, agencies(name, short_name))').order('submitted_at', { ascending: true }).limit(500)
  if (statusFilter === 'open') query = query.in('status', ['pending', 'changes_requested'])
  else if (statusFilter !== 'all') query = query.eq('status', statusFilter)
  const { data: submissions, error } = await query
  const rows = (submissions ?? []) as any[]

  return <>
    <PageHeader eyebrow="Credential Administration" title="Credential Verification" description="Review provider-submitted credentials without replacing the current verified credential until approval." action={<Link className="secondary-button button-link" href="/credentials">Back to Credentials</Link>} />
    {qs.notice && <div className="banner success"><div><strong>Submission updated</strong><span>{qs.notice}</span></div></div>}
    {qs.error && <div className="banner danger"><div><strong>Credential action failed</strong><span>{qs.error}</span></div></div>}

    <form className="filter-bar" method="get">
      <div className="results-meta"><strong>{rows.length}</strong> visible submission{rows.length === 1 ? '' : 's'}</div>
      <select name="status" defaultValue={statusFilter}><option value="open">Open review queue</option><option value="pending">Pending</option><option value="changes_requested">Changes requested</option><option value="approved">Approved</option><option value="rejected">Rejected</option><option value="all">All visible submissions</option></select>
      <button className="secondary-button" type="submit">Apply</button>
    </form>

    <div className="table-card">{error ? <div className="empty-state compact danger-text"><strong>Unable to load submissions</strong><span>{error.message}</span></div> : rows.length === 0 ? <div className="empty-state compact"><strong>No credential submissions match this view</strong><span>Provider submissions requiring your review will appear here.</span></div> : <table><thead><tr><th>Provider</th><th>Credential</th><th>Expiration</th><th>Submitted</th><th>Status</th><th></th></tr></thead><tbody>{rows.map((row:any) => <tr key={row.id}>
      <td><strong>{row.providers?.first_name} {row.providers?.last_name}</strong><div className="muted-code">{row.providers?.provider_number || 'No System ID'}</div></td>
      <td><strong>{row.credential_types?.name}</strong><div className="muted-code">{row.credential_types?.scope_type === 'agency' ? (row.credential_types?.agencies?.short_name || row.credential_types?.agencies?.name || 'Agency') : 'GEAEMS System'}</div></td>
      <td>{formatDate(row.expiration_date)}</td><td>{formatDate(row.submitted_at?.slice(0,10))}</td><td><span className={`pill ${row.status === 'pending' ? 'amber' : row.status === 'approved' ? 'green' : row.status === 'rejected' ? 'red' : ''}`}>{titleCase(row.status)}</span></td><td className="table-action"><Link href={`/credentials/submissions/${row.id}`}>Review</Link></td>
    </tr>)}</tbody></table>}</div>
  </>
}
