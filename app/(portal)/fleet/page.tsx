import type { Metadata } from 'next'
import Link from 'next/link'
import { createClient } from '@/lib/supabase/server'
import { PageHeader } from '@/components/page-header'
import { bulkSetVehicleActive } from './actions'

export const metadata: Metadata = { title: 'Fleet' }
type Props = { searchParams: Promise<{ q?: string; agency?: string; status?: string; view?: string; notice?: string; error?: string }> }

export default async function FleetPage({ searchParams }: Props) {
  const filters = await searchParams
  const supabase = await createClient()
  const view = filters.view === 'archived' ? 'archived' : filters.view === 'all' ? 'all' : 'active'

  let vehicleQuery = supabase
    .from('vehicles')
    .select('id, agency_id, vehicle_status_id, unit_number, fleet_number, vin, year, make, model, license_plate, license_plate_state, active, agencies(name, short_name), vehicle_types(name), vehicle_statuses(name)')
    .order('unit_number')
    .limit(1000)

  if (view === 'active') vehicleQuery = vehicleQuery.eq('active', true)
  if (view === 'archived') vehicleQuery = vehicleQuery.eq('active', false)

  const [{ data, error }, { data: agencies }, { data: statuses }] = await Promise.all([
    vehicleQuery,
    supabase.from('agencies').select('id, name').eq('active', true).order('name'),
    supabase.from('vehicle_statuses').select('id, name').eq('active', true).order('sort_order'),
  ])

  const q = (filters.q ?? '').trim().toLowerCase()
  let rows = (data ?? []) as any[]
  if (q) rows = rows.filter((r) => [r.unit_number, r.fleet_number, r.vin, r.make, r.model, r.license_plate].some((v) => String(v ?? '').toLowerCase().includes(q)))
  if (filters.agency) rows = rows.filter((r) => r.agency_id === filters.agency)
  if (filters.status) rows = rows.filter((r) => r.vehicle_status_id === filters.status)

  const archiveMode = view === 'archived'
  const bulkLabel = archiveMode ? 'Restore selected' : 'Archive selected'

  return <>
    <PageHeader
      title="Fleet"
      description="Vehicle registry, licensing and compliance by agency."
      action={<div className="inline-actions">
        {view !== 'archived' && <Link className="secondary-button small button-link" href="/fleet?view=archived">Archived vehicles</Link>}
        {view === 'archived' && <Link className="secondary-button small button-link" href="/fleet">Current fleet</Link>}
        <Link className="primary-button small button-link" href="/fleet/new">Add vehicle</Link>
      </div>}
    />

    {filters.notice && <div className="banner success"><div><strong>Fleet updated</strong><span>{filters.notice}</span></div></div>}
    {filters.error && <div className="banner danger"><div><strong>Unable to update fleet</strong><span>{filters.error}</span></div></div>}

    {view === 'archived' && <div className="banner info"><div><strong>Archived vehicle records</strong><span>Archived vehicles are kept for historical inspection, licensing and audit records but are excluded from the active fleet, new inspections, compliance dashboards and standard operational reports.</span></div></div>}

    <form className="filter-bar fleet-filter" method="get">
      <label className="search-field"><span className="sr-only">Search fleet</span><input name="q" defaultValue={filters.q ?? ''} placeholder="Search unit, VIN, plate, make or model" /></label>
      <select name="agency" defaultValue={filters.agency ?? ''}><option value="">All agencies</option>{agencies?.map((a) => <option key={a.id} value={a.id}>{a.name}</option>)}</select>
      <select name="status" defaultValue={filters.status ?? ''}><option value="">All statuses</option>{statuses?.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}</select>
      <select name="view" defaultValue={view}><option value="active">Current fleet</option><option value="archived">Archived vehicles</option><option value="all">All vehicles</option></select>
      <button className="secondary-button" type="submit">Filter</button>
      {(filters.q || filters.agency || filters.status || view !== 'active') && <Link className="text-link" href="/fleet">Clear</Link>}
    </form>

    <div className="results-meta">Showing <strong>{rows.length}</strong> {view === 'archived' ? 'archived ' : view === 'active' ? 'current ' : ''}vehicle{rows.length === 1 ? '' : 's'}</div>

    {error ? <div className="table-card"><div className="empty-state danger-text">{error.message}</div></div> : rows.length === 0 ? <div className="table-card"><div className="empty-state"><strong>{view === 'archived' ? 'No archived vehicles' : 'No vehicles found'}</strong><span>{view === 'archived' ? 'Vehicles you archive will remain available here with their historical records intact.' : 'Add a vehicle or change the current filters.'}</span></div></div> : <form action={bulkSetVehicleActive}>
      <input type="hidden" name="active" value={archiveMode ? 'true' : 'false'} />
      <input type="hidden" name="return_view" value={view} />
      {view !== 'all' && <div className="form-actions" style={{justifyContent:'flex-end', marginBottom:'10px'}}><button className={archiveMode ? 'secondary-button' : 'secondary-button danger-outline'} type="submit">{bulkLabel}</button></div>}
      <div className="table-card"><table>
        <thead><tr>{view !== 'all' && <th style={{width:'42px'}}><span className="sr-only">Select</span></th>}<th>Unit</th><th>Agency</th><th>Vehicle</th><th>Type</th><th>Plate</th><th>Status</th><th></th></tr></thead>
        <tbody>{rows.map((r) => <tr key={r.id}>
          {view !== 'all' && <td><input type="checkbox" name="vehicle_ids" value={r.id} aria-label={`Select ${r.unit_number || r.fleet_number || 'vehicle'}`} /></td>}
          <td><strong>{r.unit_number || r.fleet_number || 'Unnumbered'}</strong>{r.fleet_number && r.unit_number && <div className="muted-code">Fleet {r.fleet_number}</div>}</td>
          <td>{r.agencies?.short_name || r.agencies?.name || '—'}</td>
          <td>{[r.year, r.make, r.model].filter(Boolean).join(' ') || '—'}</td>
          <td>{r.vehicle_types?.name || '—'}</td>
          <td>{r.license_plate ? `${r.license_plate}${r.license_plate_state ? ` · ${r.license_plate_state}` : ''}` : '—'}</td>
          <td>{r.active ? <span className="pill green">{r.vehicle_statuses?.name || 'Active'}</span> : <span className="pill gray">Archived</span>}</td>
          <td className="table-action"><Link href={`/fleet/${r.id}`}>Open</Link></td>
        </tr>)}</tbody>
      </table></div>
    </form>}
  </>
}
