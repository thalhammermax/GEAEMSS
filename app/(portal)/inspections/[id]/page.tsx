import type { Metadata } from 'next'
import Link from 'next/link'
import { notFound, redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { PageHeader } from '@/components/page-header'
import { DigitalInspectionForm } from '@/components/digital-inspection-form'
import { formatDate, titleCase } from '@/lib/format'

export const metadata: Metadata = { title: 'Vehicle Inspection' }
type Props = { params: Promise<{ id: string }>; searchParams: Promise<{ error?: string; saved?: string; submitted?: string }> }

export default async function InspectionPage({ params, searchParams }: Props) {
  const { id } = await params
  const qs = await searchParams
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  const [{ data: roles }, { data: accessRows }] = await Promise.all([
    supabase.from('user_roles').select('role').eq('user_id', user!.id),
    supabase.from('user_agency_access').select('agency_id, can_manage_fleet').eq('user_id', user!.id),
  ])
  const roleNames = new Set((roles ?? []).map((r:any)=>r.role))
  const isSystemAdmin = roleNames.has('system_admin')
  const isSystemInspector = roleNames.has('system_inspector')
  const isAgencyAdmin = roleNames.has('agency_admin')
  if (!isSystemAdmin && !isSystemInspector && !isAgencyAdmin) redirect('/my-profile')

  const { data: inspection, error } = await supabase.from('vehicle_inspections').select('*, vehicles(id, agency_id, vehicle_type_id, unit_number, fleet_number, year, make, model, agencies(name, short_name), vehicle_types(name, code)), inspection_types(name)').eq('id', id).maybeSingle()
  if (error || !inspection) notFound()

  const { data: deficiencies } = await supabase.from('vehicle_inspection_deficiencies').select('id, form_item_id, description, severity, status, correction_due_date, correction_notes').eq('vehicle_inspection_id', id).order('created_at')

  if (!inspection.form_version_id) {
    return <>
      <PageHeader eyebrow="Inspections" title={`${inspection.vehicles?.unit_number || 'Vehicle'} inspection`} description={`${formatDate(inspection.inspection_date)} · ${inspection.inspection_types?.name || 'Legacy inspection'}`} action={<Link className="secondary-button button-link small" href="/inspections">Back to inspections</Link>} />
      <section className="form-card"><div className="form-card-heading"><div><span>Legacy inspection record</span><h2>{titleCase(inspection.result || inspection.workflow_status)}</h2></div></div><div className="detail-list"><div><dt>Inspector</dt><dd>{inspection.inspector_name || '—'}</dd></div><div><dt>Organization</dt><dd>{inspection.inspector_organization || '—'}</dd></div><div><dt>Location</dt><dd>{inspection.inspection_location || '—'}</dd></div><div><dt>Odometer</dt><dd>{inspection.odometer ?? '—'}</dd></div></div></section>
      {!!deficiencies?.length && <section className="panel"><div className="panel-heading"><h3>Deficiencies</h3><span>{deficiencies.length} recorded</span></div>{deficiencies.map((d:any)=><div className="mini-row" key={d.id}><span>{d.description}</span><strong>{titleCase(d.status)}</strong></div>)}</section>}
    </>
  }

  const [{ data: formVersion }, { data: responses }] = await Promise.all([
    supabase.from('inspection_form_versions').select('id, template_id, version_number, status').eq('id', inspection.form_version_id).maybeSingle(),
    supabase.from('inspection_item_responses').select('id, form_item_id, status, observed_value, notes').eq('vehicle_inspection_id', id),
  ])
  if (!formVersion) notFound()
  const [{ data: template }, { data: sections }] = await Promise.all([
    supabase.from('inspection_form_templates').select('id, code, name, scope_type, agency_id, vehicle_type_id').eq('id', formVersion.template_id).maybeSingle(),
    supabase.from('inspection_form_sections').select('id, title, sort_order, inspection_form_items(id, label, requirement_text, response_type, allow_na, required, sort_order)').eq('form_version_id', formVersion.id).order('sort_order'),
  ])
  if (!template) notFound()

  const agencyFleetAccess = (accessRows ?? []).some((row:any) => row.agency_id === inspection.vehicles?.agency_id && row.can_manage_fleet)
  const canEditDraft = inspection.workflow_status === 'draft' && (
    isSystemAdmin
    || (template.scope_type === 'system' && isSystemInspector)
    || (template.scope_type === 'agency' && isAgencyAdmin && agencyFleetAccess)
  )
  const readOnly = !canEditDraft
  const statusLabel = inspection.workflow_status === 'draft' ? 'Draft' : titleCase(inspection.result || 'submitted')

  return <>
    <PageHeader eyebrow="Inspections" title={`${inspection.vehicles?.unit_number || inspection.vehicles?.fleet_number || 'Vehicle'} inspection`} description={`${formatDate(inspection.inspection_date)} · ${statusLabel}`} action={<Link className="secondary-button button-link small" href="/inspections">Back to inspections</Link>} />
    {qs.saved && <div className="banner success"><div><strong>Draft saved</strong><span>You can return to this inspection later and continue where you left off.</span></div></div>}
    {qs.submitted && <div className="banner success"><div><strong>Inspection submitted</strong><span>The inspection is locked and any deficient items have been added to corrective-action tracking.</span></div></div>}
    {qs.error && <div className="banner danger"><div><strong>Inspection was not saved</strong><span>{qs.error}</span></div></div>}
    {readOnly && !!deficiencies?.length && <div className="banner warning"><div><strong>{deficiencies.length} deficiency{deficiencies.length === 1 ? '' : 'ies'} recorded</strong><span>{deficiencies.filter((d:any)=>d.status === 'open').length} remain open.</span></div></div>}
    <DigitalInspectionForm inspectionId={inspection.id} vehicle={inspection.vehicles} template={template} formVersion={formVersion} sections={(sections ?? []) as any[]} responses={responses ?? []} readOnly={readOnly} defaults={inspection} />
  </>
}
