import type { Metadata } from 'next'
import Link from 'next/link'
import { createClient } from '@/lib/supabase/server'
import { PageHeader } from '@/components/page-header'
import { DigitalInspectionForm } from '@/components/digital-inspection-form'

export const metadata: Metadata = { title: 'Start Inspection' }
type Props = { searchParams: Promise<{ vehicle?: string; error?: string }> }

export default async function StartInspectionPage({ searchParams }: Props) {
  const qs = await searchParams
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  const [{ data: roles }, { data: accessRows }, { data: profile }] = await Promise.all([
    supabase.from('user_roles').select('role').eq('user_id', user!.id),
    supabase.from('user_agency_access').select('agency_id, can_manage_fleet').eq('user_id', user!.id),
    supabase.from('profiles').select('display_name').eq('id', user!.id).maybeSingle(),
  ])
  const roleNames = new Set((roles ?? []).map((r:any)=>r.role))
  const isSystemAdmin = roleNames.has('system_admin')
  const isSystemInspector = roleNames.has('system_inspector')
  const canPerformSystemInspection = isSystemAdmin || isSystemInspector
  const manageableAgencyIds = (accessRows ?? []).filter((r:any)=>r.can_manage_fleet).map((r:any)=>r.agency_id)

  let vehicleQuery = supabase.from('vehicles').select('id, agency_id, vehicle_type_id, unit_number, fleet_number, year, make, model, active, agencies(name, short_name), vehicle_types(name, code)').eq('active', true).order('unit_number')
  if (!canPerformSystemInspection) {
    if (!manageableAgencyIds.length) return <><PageHeader eyebrow="Inspections" title="Start Inspection" description="Perform a digital vehicle inspection." /><div className="empty-state"><strong>No inspection access</strong><span>GEAEMS System inspections require the System Inspector or System Administrator role. Agency inspections require Fleet management permission and an agency-owned inspection form.</span></div></>
    vehicleQuery = vehicleQuery.in('agency_id', manageableAgencyIds)
  }
  const { data: vehicles } = await vehicleQuery
  // Supabase's generated relationship type can represent joined to-one relations as arrays.
  // Normalize this page to a UI-facing row type; RLS still governs the underlying query.
  const vehicleRows = (vehicles ?? []) as any[]

  if (!qs.vehicle) {
    return <>
      <PageHeader eyebrow="Inspections" title="Start Inspection" description="Choose the vehicle you are inspecting. The portal will load the correct GEAEMS checklist for its vehicle type." />
      <div className="table-card">{!vehicleRows.length ? <div className="empty-state"><strong>No inspectable vehicles found</strong><span>Add a fleet vehicle or grant Fleet management access first.</span></div> : <table><thead><tr><th>Unit</th><th>Agency</th><th>Vehicle</th><th>Inspection profile</th><th></th></tr></thead><tbody>{vehicleRows.map((v:any)=><tr key={v.id}><td><strong>{v.unit_number || v.fleet_number || 'Unnumbered'}</strong></td><td>{v.agencies?.short_name || v.agencies?.name || '—'}</td><td>{[v.year,v.make,v.model].filter(Boolean).join(' ') || '—'}</td><td>{v.vehicle_types?.name || 'Not assigned'}</td><td className="table-action"><Link href={`/inspections/new?vehicle=${v.id}`}>Inspect</Link></td></tr>)}</tbody></table>}</div>
    </>
  }

  const vehicle = vehicleRows.find((v:any)=>v.id === qs.vehicle)
  if (!vehicle) return <><PageHeader eyebrow="Inspections" title="Start Inspection" description="Perform a digital vehicle inspection." /><div className="banner danger"><div><strong>Vehicle unavailable</strong><span>The vehicle was not found or you do not have permission to inspect it.</span></div></div><Link className="secondary-button button-link" href="/inspections/new">Choose another vehicle</Link></>

  const { data: templates } = await supabase.from('inspection_form_templates').select('id, code, name, scope_type, agency_id, vehicle_type_id, inspection_type_id').eq('vehicle_type_id', vehicle.vehicle_type_id).eq('active', true)
  const template = canPerformSystemInspection
    ? (templates ?? []).find((t:any)=>t.scope_type === 'system')
    : (templates ?? []).find((t:any)=>t.scope_type === 'agency' && t.agency_id === vehicle.agency_id)
  if (!template) return <><PageHeader eyebrow="Inspections" title="No inspection form available" description={`${vehicle.unit_number || 'This vehicle'} does not have an inspection form you are authorized to perform.`} /><div className="banner warning"><div><strong>{canPerformSystemInspection ? 'No GEAEMS System form assigned' : 'No agency inspection form assigned'}</strong><span>{canPerformSystemInspection ? 'The vehicle must use one of the GEAEMS inspection vehicle types with a published System form.' : 'GEAEMS System inspections can only be performed by a System Inspector or System Administrator. Your agency must have its own inspection form to perform an agency inspection.'}</span></div></div><Link className="secondary-button button-link" href="/inspections">Back to inspections</Link></>

  const { data: versions } = await supabase.from('inspection_form_versions').select('id, version_number, status').eq('template_id', template.id).eq('status','published').order('version_number',{ascending:false}).limit(1)
  const formVersion = versions?.[0]
  if (!formVersion) return <div className="empty-state"><strong>No published form version</strong><span>System Administration must publish an inspection form before it can be performed.</span></div>

  const { data: sections } = await supabase.from('inspection_form_sections').select('id, title, sort_order, inspection_form_items(id, label, requirement_text, allow_na, required, sort_order)').eq('form_version_id', formVersion.id).order('sort_order')

  return <>
    <PageHeader eyebrow={template.scope_type === 'system' ? 'GEAEMS System Inspection' : 'Agency Inspection'} title={`Inspect ${vehicle.unit_number || vehicle.fleet_number || 'vehicle'}`} description={`${vehicle.agencies?.name || ''} · ${vehicle.vehicle_types?.name || ''}`} />
    {qs.error && <div className="banner danger"><div><strong>Inspection was not saved</strong><span>{qs.error}</span></div></div>}
    <DigitalInspectionForm vehicle={vehicle} template={template} formVersion={formVersion} sections={(sections ?? []) as any[]} defaults={{ inspector_name: profile?.display_name ?? '', inspector_organization: vehicle.agencies?.name ?? '' }} />
  </>
}
