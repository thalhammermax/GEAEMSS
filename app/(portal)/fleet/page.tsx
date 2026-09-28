import type { Metadata } from 'next'
import { createClient } from '@/lib/supabase/server'
import { PageHeader } from '@/components/page-header'

export const metadata: Metadata = { title: 'Fleet' }

export default async function FleetPage() {
  const supabase = await createClient()
  const { data, error } = await supabase.from('vehicles').select('id, unit_number, fleet_number, year, make, model, license_plate, license_plate_state, active, agencies(name, short_name), vehicle_types(name), vehicle_statuses(name)').order('unit_number').limit(250)
  const rows = (data ?? []) as any[]
  return <><PageHeader title="Fleet" description="Vehicle registry, licensing and compliance by agency." action={<button className="primary-button small" disabled>Add vehicle</button>} />
    <div className="table-card">{error ? <div className="empty-state danger-text">{error.message}</div> : rows.length === 0 ? <div className="empty-state"><strong>No vehicles yet</strong><span>The fleet module is ready. Vehicles will appear here as they are added.</span></div> : <table><thead><tr><th>Unit</th><th>Agency</th><th>Vehicle</th><th>Type</th><th>Plate</th><th>Status</th></tr></thead><tbody>{rows.map((r) => <tr key={r.id}><td><strong>{r.unit_number || r.fleet_number || 'Unnumbered'}</strong></td><td>{r.agencies?.short_name || r.agencies?.name || '—'}</td><td>{[r.year, r.make, r.model].filter(Boolean).join(' ') || '—'}</td><td>{r.vehicle_types?.name || '—'}</td><td>{r.license_plate ? `${r.license_plate}${r.license_plate_state ? ` · ${r.license_plate_state}` : ''}` : '—'}</td><td><span className="pill green">{r.vehicle_statuses?.name || (r.active ? 'Active' : 'Inactive')}</span></td></tr>)}</tbody></table>}</div></>
}
