import type { Metadata } from 'next'
import Link from 'next/link'
import { createClient } from '@/lib/supabase/server'
import { PageHeader } from '@/components/page-header'
import { formatDate, titleCase } from '@/lib/format'

export const metadata: Metadata = { title: 'Inspections' }

export default async function InspectionsPage() {
  const supabase = await createClient()
  const [{ data: inspections, error }, { data: deficiencies }] = await Promise.all([
    supabase.from('vehicle_inspections').select('id, inspection_date, workflow_status, result, next_due_date, inspector_name, vehicles(unit_number, fleet_number, agencies(short_name, name)), inspection_types(name)').order('created_at', { ascending: false }).limit(200),
    supabase.from('vehicle_inspection_deficiencies').select('id, description, severity, status, correction_due_date').eq('status', 'open').order('correction_due_date', { ascending: true }).limit(100),
  ])
  const rows = (inspections ?? []) as any[]
  const drafts = rows.filter((r)=>r.workflow_status === 'draft').length
  const submitted = rows.filter((r)=>r.workflow_status === 'submitted').length
  const failed = rows.filter((r)=>['failed','out_of_service'].includes(r.result)).length

  return <>
    <PageHeader title="Inspections" description="Perform GEAEMS vehicle inspections, resume drafts, review results and track deficiencies." action={<Link className="primary-button small button-link" href="/inspections/new">Start inspection</Link>} />
    <div className="summary-strip"><div><span>Recent records</span><strong>{rows.length}</strong></div><div><span>Drafts</span><strong>{drafts}</strong></div><div><span>Submitted</span><strong>{submitted}</strong></div><div><span>Failed / OOS</span><strong>{failed}</strong></div><div><span>Open deficiencies</span><strong>{deficiencies?.length ?? 0}</strong></div></div>
    {(deficiencies?.length ?? 0) > 0 && <div className="banner warning"><div><strong>{deficiencies?.length} open deficiencies</strong><span>Corrective-action tracking is active for submitted inspections.</span></div></div>}
    <div className="table-card">{error ? <div className="empty-state danger-text">{error.message}</div> : rows.length === 0 ? <div className="empty-state"><strong>No inspection records yet</strong><span>Choose Start inspection to perform the first digital vehicle inspection.</span></div> : <table><thead><tr><th>Date</th><th>Unit</th><th>Inspection</th><th>Status</th><th>Next due</th><th>Inspector</th><th></th></tr></thead><tbody>{rows.map((r) => {
      const label = r.workflow_status === 'draft' ? 'Draft' : titleCase(r.result || 'submitted')
      const cls = r.workflow_status === 'draft' ? 'amber' : r.result === 'passed' ? 'green' : r.result === 'passed_with_deficiencies' ? 'amber' : 'red'
      return <tr key={r.id}><td>{formatDate(r.inspection_date)}</td><td><strong>{r.vehicles?.unit_number || r.vehicles?.fleet_number || '—'}</strong><div className="muted-code">{r.vehicles?.agencies?.short_name || r.vehicles?.agencies?.name || ''}</div></td><td>{r.inspection_types?.name || '—'}</td><td><span className={`pill ${cls}`}>{label}</span></td><td>{formatDate(r.next_due_date)}</td><td>{r.inspector_name || '—'}</td><td className="table-action"><Link href={`/inspections/${r.id}`}>{r.workflow_status === 'draft' ? 'Resume' : 'Open'}</Link></td></tr>
    })}</tbody></table>}</div>
  </>
}
