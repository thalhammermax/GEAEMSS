import type { Metadata } from 'next'
import Link from 'next/link'
import { createClient } from '@/lib/supabase/server'
import { PageHeader } from '@/components/page-header'

export const metadata: Metadata = { title: 'Fleet' }
type Props = { searchParams: Promise<{ q?: string; agency?: string; status?: string }> }

export default async function FleetPage({ searchParams }: Props) {
  const filters = await searchParams
  const supabase = await createClient()
  const [{ data, error }, { data: agencies }, { data: statuses }] = await Promise.all([
    supabase.from('vehicles').select('id, agency_id, vehicle_status_id, unit_number, fleet_number, vin, year, make, model, license_plate, license_plate_state, active, agencies(name, short_name), vehicle_types(name), vehicle_statuses(name)').order('unit_number').limit(1000),
    supabase.from('agencies').select('id, name').eq('active', true).order('name'),
    supabase.from('vehicle_statuses').select('id, name').eq('active', true).order('sort_order'),
  ])
  const q = (filters.q ?? '').trim().toLowerCase()
  let rows = (data ?? []) as any[]
  if (q) rows = rows.filter((r) => [r.unit_number, r.fleet_number, r.vin, r.make, r.model, r.license_plate].some((v) => String(v ?? '').toLowerCase().includes(q)))
  if (filters.agency) rows = rows.filter((r) => r.agency_id === filters.agency)
  if (filters.status) rows = rows.filter((r) => r.vehicle_status_id === filters.status)

  return <>
    <PageHeader title="Fleet" description="Vehicle registry, licensing and compliance by agency." action={<Link className="primary-button small button-link" href="/fleet/new">Add vehicle</Link>} />
    <form className="filter-bar fleet-filter" method="get">
      <label className="search-field"><span className="sr-only">Search fleet</span><input name="q" defaultValue={filters.q ?? ''} placeholder="Search unit, VIN, plate, make or model" /></label>
      <select name="agency" defaultValue={filters.agency ?? ''}><option value="">All agencies</option>{agencies?.map((a) => <option key={a.id} value={a.id}>{a.name}</option>)}</select>
      <select name="status" defaultValue={filters.status ?? ''}><option value="">All statuses</option>{statuses?.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}</select>
      <button className="secondary-button" type="submit">Filter</button>
      {(filters.q || filters.agency || filters.status) && <Link className="text-link" href="/fleet">Clear</Link>}
    </form>
    <div className="results-meta">Showing <strong>{rows.length}</strong> vehicle{rows.length === 1 ? '' : 's'}</div>
    <div className="table-card">{error ? <div className="empty-state danger-text">{error.message}</div> : rows.length === 0 ? <div className="empty-state"><strong>No vehicles found</strong><span>Add a vehicle or change the current filters.</span></div> : <table><thead><tr><th>Unit</th><th>Agency</th><th>Vehicle</th><th>Type</th><th>Plate</th><th>Status</th><th></th></tr></thead><tbody>{rows.map((r) => <tr key={r.id}><td><strong>{r.unit_number || r.fleet_number || 'Unnumbered'}</strong>{r.fleet_number && r.unit_number && <div className="muted-code">Fleet {r.fleet_number}</div>}</td><td>{r.agencies?.short_name || r.agencies?.name || '—'}</td><td>{[r.year, r.make, r.model].filter(Boolean).join(' ') || '—'}</td><td>{r.vehicle_types?.name || '—'}</td><td>{r.license_plate ? `${r.license_plate}${r.license_plate_state ? ` · ${r.license_plate_state}` : ''}` : '—'}</td><td><span className={`pill ${r.active ? 'green' : ''}`}>{r.vehicle_statuses?.name || (r.active ? 'Active' : 'Inactive')}</span></td><td className="table-action"><Link href={`/fleet/${r.id}`}>Open</Link></td></tr>)}</tbody></table>}</div>
  </>
}
