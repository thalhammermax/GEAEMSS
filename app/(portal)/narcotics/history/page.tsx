import type { Metadata } from 'next'
import Link from 'next/link'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { PageHeader } from '@/components/page-header'
import { formatDate } from '@/lib/format'
import { relationOne } from '@/lib/narcotics'

export const metadata: Metadata = { title: 'Narcotics History' }

type Props = {
  searchParams: Promise<{
    agency?: string
    vehicle?: string
    from?: string
    to?: string
    discrepancy?: string
  }>
}

export default async function NarcoticsHistoryPage({ searchParams }: Props) {
  const qs = await searchParams
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const [{ data: roles }, { data: access }] = await Promise.all([
    supabase.from('user_roles').select('role').eq('user_id', user.id),
    supabase.from('user_agency_access').select('agency_id').eq('user_id', user.id),
  ])

  const roleNames = new Set((roles ?? []).map((row: any) => row.role))
  const isSystemAdmin = roleNames.has('system_admin')
  const isAgencyAdmin = roleNames.has('agency_admin')
  if (!isSystemAdmin && !isAgencyAdmin) redirect('/narcotics')

  const administeredAgencyIds = (access ?? []).map((row: any) => row.agency_id)

  let agenciesQuery = supabase.from('agencies').select('id, name, short_name').eq('active', true).order('name')
  let vehiclesQuery = supabase.from('vehicles').select('id, agency_id, unit_number, fleet_number').eq('active', true).eq('narcotics_count_required', true).order('unit_number')

  if (!isSystemAdmin) {
    if (administeredAgencyIds.length === 0) {
      return <>
        <PageHeader eyebrow="Narcotics" title="Historical counts" description="Submitted daily narcotics count records for agencies you administer." action={<Link className="secondary-button button-link" href="/narcotics">Back to Narcotics</Link>} />
        <div className="empty-state"><strong>No agency administration access</strong><span>No narcotics history is available because this account is not assigned as an administrator for an agency.</span></div>
      </>
    }
    agenciesQuery = agenciesQuery.in('id', administeredAgencyIds)
    vehiclesQuery = vehiclesQuery.in('agency_id', administeredAgencyIds)
  }

  const [{ data: agencies }, { data: vehicles }] = await Promise.all([agenciesQuery, vehiclesQuery])
  const allowedAgencyIds = new Set((agencies ?? []).map((agency: any) => agency.id))
  const selectedAgency = qs.agency && (isSystemAdmin || allowedAgencyIds.has(qs.agency)) ? qs.agency : ''
  const selectedVehicle = qs.vehicle && (vehicles ?? []).some((vehicle: any) => vehicle.id === qs.vehicle) ? qs.vehicle : ''

  let historyQuery = supabase
    .from('narcotics_counts')
    .select('id, agency_id, vehicle_id, count_date, status, has_discrepancy, seal_number, prior_seal_number, signed_name, signed_at, notes, vehicles(unit_number, fleet_number, agencies(name, short_name)), narcotics_count_templates(name)')
    .eq('status', 'submitted')
    .order('count_date', { ascending: false })
    .order('signed_at', { ascending: false })
    .limit(500)

  if (!isSystemAdmin) historyQuery = historyQuery.in('agency_id', administeredAgencyIds)
  if (selectedAgency) historyQuery = historyQuery.eq('agency_id', selectedAgency)
  if (selectedVehicle) historyQuery = historyQuery.eq('vehicle_id', selectedVehicle)
  if (qs.from) historyQuery = historyQuery.gte('count_date', qs.from)
  if (qs.to) historyQuery = historyQuery.lte('count_date', qs.to)
  if (qs.discrepancy === 'yes') historyQuery = historyQuery.eq('has_discrepancy', true)
  if (qs.discrepancy === 'no') historyQuery = historyQuery.eq('has_discrepancy', false)

  const { data: counts, error } = await historyQuery
  const filteredVehicles = selectedAgency ? (vehicles ?? []).filter((vehicle: any) => vehicle.agency_id === selectedAgency) : (vehicles ?? [])

  return <>
    <PageHeader
      eyebrow="Narcotics"
      title="Historical counts"
      description={isSystemAdmin ? 'Submitted daily narcotics count records across the GEAEMS System.' : 'Submitted daily narcotics count records for agencies you administer.'}
      action={<Link className="secondary-button button-link" href="/narcotics">Back to Narcotics</Link>}
    />

    {error && <div className="banner danger"><div><strong>History could not be loaded</strong><span>{error.message}</span></div></div>}

    <form className="filter-bar narcotics-history-filter" method="get">
      <select name="agency" defaultValue={selectedAgency} aria-label="Agency">
        <option value="">All agencies</option>
        {(agencies ?? []).map((agency: any) => <option key={agency.id} value={agency.id}>{agency.short_name || agency.name}</option>)}
      </select>
      <select name="vehicle" defaultValue={selectedVehicle} aria-label="Vehicle">
        <option value="">All apparatus</option>
        {filteredVehicles.map((vehicle: any) => <option key={vehicle.id} value={vehicle.id}>{vehicle.unit_number || vehicle.fleet_number || 'Unnumbered apparatus'}</option>)}
      </select>
      <input name="from" type="date" defaultValue={qs.from || ''} aria-label="From date" />
      <input name="to" type="date" defaultValue={qs.to || ''} aria-label="To date" />
      <select name="discrepancy" defaultValue={qs.discrepancy || ''} aria-label="Discrepancy">
        <option value="">All results</option>
        <option value="yes">Discrepancies only</option>
        <option value="no">No discrepancies</option>
      </select>
      <button className="secondary-button small" type="submit">Filter</button>
      <Link className="text-button" href="/narcotics/history">Clear</Link>
    </form>

    <div className="summary-strip">
      <div><span>Submitted records</span><strong>{counts?.length ?? 0}</strong></div>
      <div><span>With discrepancy</span><strong>{(counts ?? []).filter((count: any) => count.has_discrepancy).length}</strong></div>
      <div><span>Without discrepancy</span><strong>{(counts ?? []).filter((count: any) => !count.has_discrepancy).length}</strong></div>
    </div>

    <div className="table-card">
      {(counts ?? []).length === 0 ? <div className="empty-state"><strong>No submitted narcotics counts match these filters.</strong><span>Historical records will appear here after a daily count is electronically signed and submitted.</span></div> : <table>
        <thead><tr><th>Date</th><th>Agency</th><th>Apparatus</th><th>Form</th><th>Seal</th><th>Signed by</th><th>Result</th><th></th></tr></thead>
        <tbody>{(counts ?? []).map((count: any) => {
          const vehicle = relationOne<any>(count.vehicles)
          const agency = relationOne<any>(vehicle?.agencies)
          const template = relationOne<any>(count.narcotics_count_templates)
          return <tr key={count.id}>
            <td><strong>{formatDate(count.count_date)}</strong>{count.signed_at && <div className="muted-code">{new Date(count.signed_at).toLocaleString()}</div>}</td>
            <td>{agency?.short_name || agency?.name || '—'}</td>
            <td><strong>{vehicle?.unit_number || vehicle?.fleet_number || 'Unnumbered'}</strong></td>
            <td>{template?.name || '—'}</td>
            <td>{count.seal_number || '—'}</td>
            <td>{count.signed_name || '—'}</td>
            <td><span className={`pill ${count.has_discrepancy ? 'red' : 'green'}`}>{count.has_discrepancy ? 'Discrepancy' : 'Matched'}</span></td>
            <td className="table-action"><Link href={`/narcotics/${count.id}`}>View log</Link></td>
          </tr>
        })}</tbody>
      </table>}
    </div>
  </>
}
