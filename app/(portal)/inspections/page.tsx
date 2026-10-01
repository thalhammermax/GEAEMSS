import type { Metadata } from 'next'
import Link from 'next/link'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { PageHeader } from '@/components/page-header'
import { formatDate, titleCase } from '@/lib/format'

export const metadata: Metadata = { title: 'Inspections' }

export default async function InspectionsPage() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  const [{ data: roles }, { data: accessRows }, { data: inspections, error }, { data: deficiencies }] = await Promise.all([
    supabase.from('user_roles').select('role').eq('user_id', user!.id),
    supabase.from('user_agency_access').select('agency_id, can_manage_fleet').eq('user_id', user!.id),
    supabase.from('vehicle_inspections').select('id, inspection_date, workflow_status, result, next_due_date, inspector_name, vehicles(agency_id, unit_number, fleet_number, agencies(short_name, name)), inspection_types(name), inspection_form_versions(inspection_form_templates(scope_type, agency_id))').order('created_at', { ascending: false }).limit(200),
    supabase.from('vehicle_inspection_deficiencies').select('id, description, severity, status, correction_due_date').eq('status', 'open').order('correction_due_date', { ascending: true }).limit(100),
  ])
  const roleNames = new Set((roles ?? []).map((r:any)=>r.role))
  const isSystemAdmin = roleNames.has('system_admin')
  const isSystemInspector = roleNames.has('system_inspector')
  const isAgencyAdmin = roleNames.has('agency_admin')
  if (!isSystemAdmin && !isSystemInspector && !isAgencyAdmin) redirect('/my-profile')
  const canManageForms = isSystemAdmin || (isAgencyAdmin && (accessRows ?? []).some((a:any) => a.can_manage_fleet))
  const canStartInspection = isSystemAdmin || isSystemInspector || (isAgencyAdmin && (accessRows ?? []).some((a:any) => a.can_manage_fleet))
  const rows = (inspections ?? []) as any[]
  const drafts = rows.filter((r)=>r.workflow_status === 'draft').length
  const submitted = rows.filter((r)=>r.workflow_status === 'submitted').length
  const failed = rows.filter((r)=>['failed','out_of_service'].includes(r.result)).length

  return <>
    <PageHeader title="Inspections" description="Perform GEAEMS vehicle inspections, resume authorized drafts, review submitted results and track deficiencies." action={<div className="inline-actions">{canManageForms && <Link className="secondary-button small button-link" href="/inspections/forms">Manage forms</Link>}{canStartInspection && <Link className="primary-button small button-link" href="/inspections/new">Start inspection</Link>}</div>} />
    <div className="summary-strip"><div><span>Recent records</span><strong>{rows.length}</strong></div><div><span>Drafts</span><strong>{drafts}</strong></div><div><span>Submitted</span><strong>{submitted}</strong></div><div><span>Failed / OOS</span><strong>{failed}</strong></div><div><span>Open deficiencies</span><strong>{deficiencies?.length ?? 0}</strong></div></div>
    {(deficiencies?.length ?? 0) > 0 && <div className="banner warning"><div><strong>{deficiencies?.length} open deficiencies</strong><span>Corrective-action tracking is active for submitted inspections.</span></div></div>}
    <div className="table-card">{error ? <div className="empty-state danger-text">{error.message}</div> : rows.length === 0 ? <div className="empty-state"><strong>No inspection records yet</strong><span>Choose Start inspection to perform the first digital vehicle inspection.</span></div> : <table><thead><tr><th>Date</th><th>Unit</th><th>Inspection</th><th>Status</th><th>Next due</th><th>Inspector</th><th></th></tr></thead><tbody>{rows.map((r) => {
      const label = r.workflow_status === 'draft' ? 'Draft' : titleCase(r.result || 'submitted')
      const cls = r.workflow_status === 'draft' ? 'amber' : r.result === 'passed' ? 'green' : r.result === 'passed_with_deficiencies' ? 'amber' : 'red'
      const template = Array.isArray(r.inspection_form_versions) ? r.inspection_form_versions[0]?.inspection_form_templates : r.inspection_form_versions?.inspection_form_templates
      const templateRow = Array.isArray(template) ? template[0] : template
      const vehicleRow = Array.isArray(r.vehicles) ? r.vehicles[0] : r.vehicles
      const canResume = r.workflow_status === 'draft' && (
        isSystemAdmin
        || (templateRow?.scope_type === 'system' && isSystemInspector)
        || (templateRow?.scope_type === 'agency' && isAgencyAdmin && (accessRows ?? []).some((a:any)=>a.agency_id === vehicleRow?.agency_id && a.can_manage_fleet))
      )
      return <tr key={r.id}><td>{formatDate(r.inspection_date)}</td><td><strong>{vehicleRow?.unit_number || vehicleRow?.fleet_number || '—'}</strong><div className="muted-code">{vehicleRow?.agencies?.short_name || vehicleRow?.agencies?.name || ''}</div></td><td>{r.inspection_types?.name || '—'}</td><td><span className={`pill ${cls}`}>{label}</span></td><td>{formatDate(r.next_due_date)}</td><td>{r.inspector_name || '—'}</td><td className="table-action"><div className="inline-actions"><Link href={`/inspections/${r.id}`}>{canResume ? 'Resume' : 'Open'}</Link><a className="text-link" href={`/inspections/${r.id}/pdf`}>PDF</a></div></td></tr>
    })}</tbody></table>}</div>
  </>
}
