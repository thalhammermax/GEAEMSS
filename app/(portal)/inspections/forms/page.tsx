import type { Metadata } from 'next'
import Link from 'next/link'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { PageHeader } from '@/components/page-header'

export const metadata: Metadata = { title: 'Inspection Forms' }

export default async function InspectionFormsPage() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const [{ data: roles }, { data: access }, { data: templates, error }, { data: versions }] = await Promise.all([
    supabase.from('user_roles').select('role').eq('user_id', user.id),
    supabase.from('user_agency_access').select('agency_id, can_manage_fleet').eq('user_id', user.id),
    supabase.from('inspection_form_templates').select('id, code, name, description, scope_type, agency_id, active, vehicle_types(name, code), inspection_types(name), agencies(name, short_name)').order('name'),
    supabase.from('inspection_form_versions').select('id, template_id, version_number, status, published_at').order('version_number', { ascending: false }),
  ])

  const roleNames = new Set((roles ?? []).map((r:any) => r.role))
  const isSystemAdmin = roleNames.has('system_admin')
  const isAgencyAdmin = roleNames.has('agency_admin')
  if (!isSystemAdmin && !isAgencyAdmin) redirect('/inspections')

  const fleetAgencyIds = new Set((access ?? []).filter((a:any) => a.can_manage_fleet).map((a:any) => a.agency_id))
  const visible = ((templates ?? []) as any[]).filter((t:any) => isSystemAdmin || (t.scope_type === 'agency' && t.agency_id && fleetAgencyIds.has(t.agency_id)))
  const versionRows = (versions ?? []) as any[]

  const canCreateAgencyForm = isSystemAdmin || (isAgencyAdmin && fleetAgencyIds.size > 0)

  return <>
    <PageHeader eyebrow="Inspections" title="Inspection form editor" description="Edit checklist content through versioned drafts. Published forms remain immutable so historical inspections always retain the exact form that was used." action={<div className="inline-actions">{canCreateAgencyForm && <Link className="primary-button button-link small" href="/inspections/forms/new">New agency form</Link>}<Link className="secondary-button button-link small" href="/inspections">Back to inspections</Link></div>} />
    <div className="banner"><div><strong>Version-safe editing</strong><span>Managing a form creates an editable draft copy. Nothing changes for inspectors until you publish the new version.</span></div></div>
    <div className="table-card">{error ? <div className="empty-state danger-text">{error.message}</div> : visible.length === 0 ? <div className="empty-state"><strong>No editable inspection forms</strong><span>System forms are managed by System Administration. Agency forms require Fleet management permission for the owning agency.</span></div> : <table><thead><tr><th>Form</th><th>Scope</th><th>Vehicle profile</th><th>Published</th><th>Draft</th><th>Status</th><th></th></tr></thead><tbody>{visible.map((t:any) => {
      const published = versionRows.find((v:any) => v.template_id === t.id && v.status === 'published')
      const draft = versionRows.find((v:any) => v.template_id === t.id && v.status === 'draft')
      const vehicleType = Array.isArray(t.vehicle_types) ? t.vehicle_types[0] : t.vehicle_types
      const agency = Array.isArray(t.agencies) ? t.agencies[0] : t.agencies
      return <tr key={t.id}><td><strong>{t.name}</strong><div className="muted-code">{t.code}</div></td><td>{t.scope_type === 'system' ? <span className="pill green">GEAEMS System</span> : <><strong>{agency?.short_name || agency?.name || 'Agency'}</strong><div className="muted-code">Agency form</div></>}</td><td>{vehicleType?.name || '—'}</td><td>{published ? `v${published.version_number}` : 'None'}</td><td>{draft ? <span className="pill amber">v{draft.version_number} draft</span> : '—'}</td><td><span className={`pill ${t.active ? 'green' : ''}`}>{t.active ? 'Active' : 'Inactive'}</span></td><td className="table-action"><Link href={`/inspections/forms/${t.id}`}>Manage</Link></td></tr>
    })}</tbody></table>}</div>
  </>
}
