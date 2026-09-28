import type { Metadata } from 'next'
import Link from 'next/link'
import { createClient } from '@/lib/supabase/server'
import { PageHeader } from '@/components/page-header'

export const metadata: Metadata = { title: 'Agencies' }

export default async function AgenciesPage() {
  const supabase = await createClient()
  const [{ data: agencies, error }, { data: affiliations }] = await Promise.all([
    supabase.from('agencies').select('id, name, short_name, active').order('name'),
    supabase.from('provider_agencies').select('agency_id').eq('active', true),
  ])

  const counts = new Map<string, number>()
  for (const row of affiliations ?? []) counts.set(row.agency_id, (counts.get(row.agency_id) ?? 0) + 1)

  return <>
    <PageHeader
      title="Agencies"
      description="Manage EMS System agencies and their provider rosters."
      action={<Link className="primary-button small button-link" href="/administration/agencies/new">Add agency</Link>}
    />
    <div className="table-card">
      {error ? <div className="empty-state danger-text">{error.message}</div> : (agencies?.length ?? 0) === 0 ?
        <div className="empty-state"><strong>No agencies configured</strong><span>Add the first participating agency to begin building the system roster.</span></div> :
        <table>
          <thead><tr><th>Agency</th><th>Abbreviation</th><th>Active providers</th><th>Status</th><th></th></tr></thead>
          <tbody>{agencies?.map((agency) => <tr key={agency.id}>
            <td><strong>{agency.name}</strong></td>
            <td>{agency.short_name || '—'}</td>
            <td>{counts.get(agency.id) ?? 0}</td>
            <td><span className={`pill ${agency.active ? 'green' : ''}`}>{agency.active ? 'Active' : 'Inactive'}</span></td>
            <td className="table-action"><Link href={`/administration/agencies/${agency.id}`}>Manage</Link></td>
          </tr>)}</tbody>
        </table>}
    </div>
  </>
}
