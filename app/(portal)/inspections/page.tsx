import type { Metadata } from 'next'
import { createClient } from '@/lib/supabase/server'
import { PageHeader } from '@/components/page-header'
import { formatDate, titleCase } from '@/lib/format'

export const metadata: Metadata = { title: 'Inspections' }

export default async function InspectionsPage() {
  const supabase = await createClient()
  const [{ data: inspections, error }, { data: deficiencies }] = await Promise.all([
    supabase.from('vehicle_inspections').select('id, inspection_date, result, next_due_date, inspector_name, vehicles(unit_number, agencies(short_name, name)), inspection_types(name)').order('inspection_date', { ascending: false }).limit(100),
    supabase.from('vehicle_inspection_deficiencies').select('id, description, severity, status, correction_due_date').eq('status', 'open').order('correction_due_date', { ascending: true }).limit(20),
  ])
  const rows = (inspections ?? []) as any[]
  return <><PageHeader title="Inspections" description="Vehicle inspection history, schedules and corrective actions." />
    {(deficiencies?.length ?? 0) > 0 && <div className="banner warning"><div><strong>{deficiencies?.length} open deficiencies</strong><span>Review corrective actions and due dates.</span></div></div>}
    <div className="table-card">{error ? <div className="empty-state danger-text">{error.message}</div> : rows.length === 0 ? <div className="empty-state"><strong>No inspection records yet</strong><span>Inspection records and deficiencies will be shown here.</span></div> : <table><thead><tr><th>Date</th><th>Unit</th><th>Inspection</th><th>Result</th><th>Next due</th><th>Inspector</th></tr></thead><tbody>{rows.map((r) => <tr key={r.id}><td>{formatDate(r.inspection_date)}</td><td><strong>{r.vehicles?.unit_number || '—'}</strong><div className="muted-code">{r.vehicles?.agencies?.short_name || r.vehicles?.agencies?.name || ''}</div></td><td>{r.inspection_types?.name || '—'}</td><td><span className={`pill ${r.result === 'passed' ? 'green' : r.result.includes('failed') || r.result === 'out_of_service' ? 'red' : 'amber'}`}>{titleCase(r.result)}</span></td><td>{formatDate(r.next_due_date)}</td><td>{r.inspector_name || '—'}</td></tr>)}</tbody></table>}</div></>
}
