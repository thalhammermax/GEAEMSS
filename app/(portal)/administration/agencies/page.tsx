import type { Metadata } from 'next'
import Link from 'next/link'
import { createClient } from '@/lib/supabase/server'
import { PageHeader } from '@/components/page-header'
import { bulkSetAgencyActive } from './actions'

export const metadata: Metadata = { title: 'Agencies' }
type Props = { searchParams: Promise<{ q?: string; view?: string; notice?: string; error?: string }> }

export default async function AgenciesPage({ searchParams }: Props) {
  const filters = await searchParams
  const supabase = await createClient()
  const view = filters.view === 'archived' ? 'archived' : filters.view === 'all' ? 'all' : 'active'

  let agencyQuery = supabase
    .from('agencies')
    .select('id, name, short_name, active')
    .order('name')
    .limit(1000)

  if (view === 'active') agencyQuery = agencyQuery.eq('active', true)
  if (view === 'archived') agencyQuery = agencyQuery.eq('active', false)

  const [{ data: agencies, error }, { data: affiliations }, { data: vehicles }] = await Promise.all([
    agencyQuery,
    supabase.from('provider_agencies').select('agency_id').eq('active', true),
    supabase.from('vehicles').select('agency_id, active'),
  ])

  const providerCounts = new Map<string, number>()
  for (const row of affiliations ?? []) providerCounts.set(row.agency_id, (providerCounts.get(row.agency_id) ?? 0) + 1)

  const vehicleCounts = new Map<string, number>()
  for (const row of vehicles ?? []) {
    if (!row.active) continue
    vehicleCounts.set(row.agency_id, (vehicleCounts.get(row.agency_id) ?? 0) + 1)
  }

  const q = (filters.q ?? '').trim().toLowerCase()
  let rows = (agencies ?? []) as any[]
  if (q) rows = rows.filter((agency) => [agency.name, agency.short_name].some((value) => String(value ?? '').toLowerCase().includes(q)))

  const archiveMode = view === 'archived'

  return <>
    <PageHeader
      title="Agencies"
      description="Manage participating EMS System agencies while preserving archived test and historical organization records."
      action={<div className="inline-actions">
        {view !== 'archived' && <Link className="secondary-button small button-link" href="/administration/agencies?view=archived">Archived agencies</Link>}
        {view === 'archived' && <Link className="secondary-button small button-link" href="/administration/agencies">Current agencies</Link>}
        <Link className="primary-button small button-link" href="/administration/agencies/new">Add agency</Link>
      </div>}
    />

    {filters.notice && <div className="banner success"><div><strong>Agencies updated</strong><span>{filters.notice}</span></div></div>}
    {filters.error && <div className="banner danger"><div><strong>Unable to update agencies</strong><span>{filters.error}</span></div></div>}

    {view === 'archived' && <div className="banner info"><div><strong>Archived agency records</strong><span>Archived agencies remain available for historical records, but they and their apparatus are excluded from normal production fleet, inspection, compliance and reporting workflows until the agency is restored.</span></div></div>}

    <form className="filter-bar" method="get">
      <label className="search-field"><span className="sr-only">Search agencies</span><input name="q" defaultValue={filters.q ?? ''} placeholder="Search agency name or abbreviation" /></label>
      <select name="view" defaultValue={view}><option value="active">Current agencies</option><option value="archived">Archived agencies</option><option value="all">All agencies</option></select>
      <button className="secondary-button" type="submit">Filter</button>
      {(filters.q || view !== 'active') && <Link className="text-link" href="/administration/agencies">Clear</Link>}
    </form>

    <div className="results-meta">Showing <strong>{rows.length}</strong> {view === 'archived' ? 'archived ' : view === 'active' ? 'current ' : ''}agenc{rows.length === 1 ? 'y' : 'ies'}</div>

    {error ? <div className="table-card"><div className="empty-state danger-text">{error.message}</div></div> : rows.length === 0 ? <div className="table-card"><div className="empty-state"><strong>{view === 'archived' ? 'No archived agencies' : 'No agencies found'}</strong><span>{view === 'archived' ? 'Agencies you archive will remain available here with their historical records intact.' : 'Add an agency or change the current filters.'}</span></div></div> : <form action={bulkSetAgencyActive}>
      <input type="hidden" name="active" value={archiveMode ? 'true' : 'false'} />
      <input type="hidden" name="return_view" value={view} />
      {view !== 'all' && <div className="form-actions" style={{justifyContent:'flex-end', marginBottom:'10px'}}><button className={archiveMode ? 'secondary-button' : 'secondary-button danger-outline'} type="submit">{archiveMode ? 'Restore selected' : 'Archive selected'}</button></div>}
      <div className="table-card"><table>
        <thead><tr>{view !== 'all' && <th style={{width:'42px'}}><span className="sr-only">Select</span></th>}<th>Agency</th><th>Abbreviation</th><th>Active providers</th><th>Current vehicles</th><th>Status</th><th></th></tr></thead>
        <tbody>{rows.map((agency) => <tr key={agency.id}>
          {view !== 'all' && <td><input type="checkbox" name="agency_ids" value={agency.id} aria-label={`Select ${agency.name}`} /></td>}
          <td><strong>{agency.name}</strong></td>
          <td>{agency.short_name || '—'}</td>
          <td>{providerCounts.get(agency.id) ?? 0}</td>
          <td>{vehicleCounts.get(agency.id) ?? 0}</td>
          <td>{agency.active ? <span className="pill green">Active</span> : <span className="pill gray">Archived</span>}</td>
          <td className="table-action"><Link href={`/administration/agencies/${agency.id}`}>Manage</Link></td>
        </tr>)}</tbody>
      </table></div>
    </form>}
  </>
}
