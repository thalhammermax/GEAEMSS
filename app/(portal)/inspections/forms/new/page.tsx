import type { Metadata } from 'next'
import Link from 'next/link'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { PageHeader } from '@/components/page-header'
import { createAgencyInspectionForm } from '../actions'

export const metadata: Metadata = { title: 'New Agency Inspection Form' }
type Props = { searchParams: Promise<{ error?: string }> }

export default async function NewAgencyInspectionFormPage({ searchParams }: Props) {
  const qs = await searchParams
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const [{ data: roles }, { data: accessRows }, { data: vehicleTypes }] = await Promise.all([
    supabase.from('user_roles').select('role').eq('user_id', user.id),
    supabase.from('user_agency_access').select('agency_id, can_manage_fleet').eq('user_id', user.id),
    supabase.from('vehicle_types').select('id, code, name').eq('active', true).order('sort_order').order('name'),
  ])

  const roleNames = new Set((roles ?? []).map((r:any) => r.role))
  const isSystemAdmin = roleNames.has('system_admin')
  const isAgencyAdmin = roleNames.has('agency_admin')
  const fleetAgencyIds = (accessRows ?? []).filter((a:any) => a.can_manage_fleet).map((a:any) => a.agency_id)

  if (!isSystemAdmin && (!isAgencyAdmin || !fleetAgencyIds.length)) redirect('/inspections/forms')

  let agencyQuery = supabase.from('agencies').select('id, name, short_name').eq('active', true).order('name')
  if (!isSystemAdmin) agencyQuery = agencyQuery.in('id', fleetAgencyIds)
  const { data: agencies } = await agencyQuery

  return <>
    <PageHeader eyebrow="Inspection Forms" title="New agency inspection form" description="Create an agency-owned checklist for one vehicle type. The new form starts as an unpublished draft so you can build it before anyone performs it." action={<Link className="secondary-button button-link small" href="/inspections/forms">Back to forms</Link>} />
    {qs.error && <div className="banner danger"><div><strong>Form was not created</strong><span>{qs.error}</span></div></div>}

    <section className="form-card">
      <div className="form-card-heading"><div><span>Agency checklist</span><h2>Form definition</h2></div><span className="pill amber">Starts as draft</span></div>
      <form action={createAgencyInspectionForm}>
        <div className="form-grid two">
          <label className="field"><span>Agency *</span><select name="agency_id" required defaultValue=""><option value="" disabled>Select agency</option>{(agencies ?? []).map((a:any)=><option key={a.id} value={a.id}>{a.short_name ? `${a.short_name} — ${a.name}` : a.name}</option>)}</select><small>You can only create forms for agencies where you have Fleet management permission.</small></label>
          <label className="field"><span>Vehicle type *</span><select name="vehicle_type_id" required defaultValue=""><option value="" disabled>Select vehicle type</option>{(vehicleTypes ?? []).map((v:any)=><option key={v.id} value={v.id}>{v.name}</option>)}</select><small>The form will be offered only for vehicles assigned this vehicle type.</small></label>
          <label className="field span-two"><span>Form name *</span><input name="name" required placeholder="e.g. Daily ALS Ambulance Readiness Check" /></label>
          <label className="field span-two"><span>Description</span><textarea name="description" rows={3} placeholder="Optional purpose or instructions for this agency checklist" /></label>
        </div>
        <div className="banner subtle"><div><strong>Agency form</strong><span>This does not change or replace the official GEAEMS System inspection form. Agency forms are available only to authorized administrators for the owning agency.</span></div></div>
        <div className="form-actions"><Link className="secondary-button button-link" href="/inspections/forms">Cancel</Link><button className="primary-button" type="submit">Create form & build checklist</button></div>
      </form>
    </section>
  </>
}
