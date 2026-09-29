import type { Metadata } from 'next'
import Link from 'next/link'
import { redirect, notFound } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { PageHeader } from '@/components/page-header'
import {
  createInspectionFormDraft,
  publishInspectionFormDraft,
  discardInspectionFormDraft,
  updateInspectionFormTemplate,
  createInspectionSection,
  updateInspectionSection,
  deleteInspectionSection,
  createInspectionItem,
  updateInspectionItem,
  deleteInspectionItem,
} from '../actions'

export const metadata: Metadata = { title: 'Edit Inspection Form' }
type Props = { params: Promise<{ id: string }>; searchParams: Promise<{ error?: string; notice?: string }> }

const RESPONSE_TYPES = [
  ['compliance', 'Compliant / Deficient'],
  ['text', 'Text'],
  ['number', 'Number'],
  ['date', 'Date'],
  ['yes_no', 'Yes / No'],
] as const

export default async function InspectionFormEditorPage({ params, searchParams }: Props) {
  const { id } = await params
  const qs = await searchParams
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const [{ data: roles }, { data: access }, { data: template, error: templateError }] = await Promise.all([
    supabase.from('user_roles').select('role').eq('user_id', user.id),
    supabase.from('user_agency_access').select('agency_id, can_manage_fleet').eq('user_id', user.id),
    supabase.from('inspection_form_templates').select('id, code, name, description, scope_type, agency_id, active, vehicle_types(name, code), inspection_types(name), agencies(name, short_name)').eq('id', id).maybeSingle(),
  ])
  if (templateError || !template) notFound()

  const roleNames = new Set((roles ?? []).map((r:any) => r.role))
  const isSystemAdmin = roleNames.has('system_admin')
  const canManageAgency = template.scope_type === 'agency' && !!template.agency_id && (access ?? []).some((a:any) => a.agency_id === template.agency_id && a.can_manage_fleet)
  if (!isSystemAdmin && !canManageAgency) redirect('/inspections/forms')

  const { data: versions } = await supabase.from('inspection_form_versions').select('id, template_id, version_number, status, source_name, published_at, published_by, created_at').eq('template_id', id).order('version_number', { ascending: false })
  const draft = (versions ?? []).find((v:any) => v.status === 'draft') as any | undefined
  const published = (versions ?? []).find((v:any) => v.status === 'published') as any | undefined

  let sections:any[] = []
  if (draft) {
    const { data } = await supabase.from('inspection_form_sections').select('id, title, sort_order, inspection_form_items(id, item_code, label, requirement_text, response_type, required, allow_na, failure_severity, requires_comment_on_fail, sort_order)').eq('form_version_id', draft.id).order('sort_order')
    sections = ((data ?? []) as any[]).map((s:any) => ({ ...s, inspection_form_items: [...(s.inspection_form_items ?? [])].sort((a:any,b:any) => a.sort_order - b.sort_order) }))
  }

  const vehicleType = Array.isArray(template.vehicle_types) ? template.vehicle_types[0] : template.vehicle_types
  const inspectionType = Array.isArray(template.inspection_types) ? template.inspection_types[0] : template.inspection_types
  const agency = Array.isArray(template.agencies) ? template.agencies[0] : template.agencies
  const itemCount = sections.reduce((sum:number, section:any) => sum + (section.inspection_form_items?.length ?? 0), 0)

  return <>
    <PageHeader eyebrow="Inspection Form Editor" title={template.name} description={`${template.scope_type === 'system' ? 'GEAEMS System' : agency?.name || 'Agency'} · ${vehicleType?.name || 'Vehicle'} · ${inspectionType?.name || 'Inspection'}`} action={<Link className="secondary-button button-link small" href="/inspections/forms">Back to forms</Link>} />
    {qs.notice && <div className="banner success"><div><strong>Saved</strong><span>{qs.notice}</span></div></div>}
    {qs.error && <div className="banner danger"><div><strong>Form action failed</strong><span>{qs.error}</span></div></div>}

    <section className="form-card">
      <div className="form-card-heading"><div><span>Definition</span><h2>Form settings</h2></div><span className={`pill ${template.active ? 'green' : ''}`}>{template.active ? 'Active' : 'Inactive'}</span></div>
      <form action={updateInspectionFormTemplate}>
        <input type="hidden" name="template_id" value={template.id}/>
        <div className="form-grid two">
          <label className="field"><span>Form name *</span><input name="name" required defaultValue={template.name}/></label>
          <label className="field"><span>Internal code</span><input value={template.code} disabled/><small>The form code remains fixed after creation.</small></label>
          <label className="field span-two"><span>Description</span><textarea name="description" rows={3} defaultValue={template.description ?? ''}/></label>
        </div>
        <label className="checkbox-row"><input type="checkbox" name="active" defaultChecked={template.active}/>Active and available for inspections</label>
        <div className="form-actions"><button className="primary-button small" type="submit">Save form settings</button></div>
      </form>
    </section>

    <section className="panel">
      <div className="panel-heading"><div><span>Version control</span><h3>Published checklist</h3></div><div className="inline-actions">{published && <span className="pill green">Published v{published.version_number}</span>}{draft && <span className="pill amber">Editing v{draft.version_number}</span>}</div></div>
      {!draft ? <div className="empty-state compact"><strong>{published ? `Version ${published.version_number} is live` : 'No version has been published yet'}</strong><span>Create an editable draft to change sections or checklist items. The live version stays untouched until you publish.</span><form action={createInspectionFormDraft}><input type="hidden" name="template_id" value={template.id}/><button className="primary-button" type="submit">Create editable draft</button></form></div> : <div className="version-action-row"><div><strong>Draft version {draft.version_number}</strong><span>{sections.length} sections · {itemCount} items. Changes here are not visible to inspectors until published.</span></div><div className="inline-actions"><form action={discardInspectionFormDraft}><input type="hidden" name="template_id" value={template.id}/><input type="hidden" name="version_id" value={draft.id}/><button className="secondary-button" type="submit">Discard draft</button></form><form action={publishInspectionFormDraft}><input type="hidden" name="template_id" value={template.id}/><input type="hidden" name="version_id" value={draft.id}/><button className="primary-button" type="submit">Publish version {draft.version_number}</button></form></div></div>}
    </section>

    {draft && <>
      <section className="section-block">
        <div className="section-title"><div><span>Draft editor</span><h2>Sections & inspection items</h2></div><div className="section-badge">{itemCount} items</div></div>
        {sections.length === 0 && <div className="empty-state"><strong>No sections yet</strong><span>Add the first section below.</span></div>}
        {sections.map((section:any) => <section className="form-card inspection-form-editor-section" key={section.id}>
          <div className="form-card-heading"><div><span>Section</span><h2>{section.title}</h2></div><span className="pill">{section.inspection_form_items?.length ?? 0} items</span></div>
          <div className="editor-section-actions">
            <form action={updateInspectionSection} className="editor-inline-form"><input type="hidden" name="template_id" value={template.id}/><input type="hidden" name="version_id" value={draft.id}/><input type="hidden" name="section_id" value={section.id}/><label className="field"><span>Section title</span><input name="title" required defaultValue={section.title}/></label><label className="field narrow-field"><span>Order</span><input name="sort_order" type="number" step="10" defaultValue={section.sort_order}/></label><button className="secondary-button small" type="submit">Save section</button></form>
            <form action={deleteInspectionSection}><input type="hidden" name="template_id" value={template.id}/><input type="hidden" name="version_id" value={draft.id}/><input type="hidden" name="section_id" value={section.id}/><button className="text-button danger-text" type="submit">Delete section</button></form>
          </div>

          <div className="inspection-form-editor-items">
            {(section.inspection_form_items ?? []).map((item:any) => <details className="editor-item" key={item.id}>
              <summary><div><strong>{item.label}</strong><span>{item.requirement_text}</span></div><div className="inline-actions"><span className="pill">{RESPONSE_TYPES.find(([key]) => key === item.response_type)?.[1] ?? item.response_type}</span>{item.required && <span className="pill green">Required</span>}</div></summary>
              <form action={updateInspectionItem} className="editor-item-form"><input type="hidden" name="template_id" value={template.id}/><input type="hidden" name="version_id" value={draft.id}/><input type="hidden" name="section_id" value={section.id}/><input type="hidden" name="item_id" value={item.id}/><div className="form-grid three"><label className="field span-two"><span>Inspection item *</span><input name="label" required defaultValue={item.label}/></label><label className="field"><span>Order</span><input name="sort_order" type="number" step="10" defaultValue={item.sort_order}/></label><label className="field span-two"><span>Requirement *</span><input name="requirement_text" required defaultValue={item.requirement_text}/></label><label className="field"><span>Response type</span><select name="response_type" defaultValue={item.response_type}>{RESPONSE_TYPES.map(([key,label]) => <option key={key} value={key}>{label}</option>)}</select></label><label className="field"><span>Failure severity</span><select name="failure_severity" defaultValue={item.failure_severity}><option value="advisory">Advisory</option><option value="deficiency">Deficiency</option><option value="critical">Critical</option></select></label></div><div className="inline-options"><label className="checkbox-row"><input type="checkbox" name="required" defaultChecked={item.required}/>Required</label><label className="checkbox-row"><input type="checkbox" name="allow_na" defaultChecked={item.allow_na}/>Allow N/A for compliance response</label><label className="checkbox-row"><input type="checkbox" name="requires_comment_on_fail" defaultChecked={item.requires_comment_on_fail}/>Require comment when deficient</label></div><div className="form-actions"><button className="primary-button small" type="submit">Save item</button></div></form>
              <form action={deleteInspectionItem} className="editor-delete-row"><input type="hidden" name="template_id" value={template.id}/><input type="hidden" name="version_id" value={draft.id}/><input type="hidden" name="section_id" value={section.id}/><input type="hidden" name="item_id" value={item.id}/><button className="text-button danger-text" type="submit">Delete item from draft</button></form>
            </details>)}
          </div>

          <details className="editor-add-block"><summary>+ Add inspection item to this section</summary><form action={createInspectionItem} className="editor-item-form"><input type="hidden" name="template_id" value={template.id}/><input type="hidden" name="version_id" value={draft.id}/><input type="hidden" name="section_id" value={section.id}/><div className="form-grid three"><label className="field span-two"><span>Inspection item *</span><input name="label" required/></label><label className="field"><span>Order</span><input name="sort_order" type="number" step="10" defaultValue={((section.inspection_form_items?.at(-1)?.sort_order ?? 0) + 10)}/></label><label className="field span-two"><span>Requirement *</span><input name="requirement_text" required placeholder="e.g. 2 each, Required, 50 mg"/></label><label className="field"><span>Response type</span><select name="response_type" defaultValue="compliance">{RESPONSE_TYPES.map(([key,label]) => <option key={key} value={key}>{label}</option>)}</select></label><label className="field"><span>Failure severity</span><select name="failure_severity" defaultValue="deficiency"><option value="advisory">Advisory</option><option value="deficiency">Deficiency</option><option value="critical">Critical</option></select></label></div><div className="inline-options"><label className="checkbox-row"><input type="checkbox" name="required" defaultChecked/>Required</label><label className="checkbox-row"><input type="checkbox" name="allow_na"/>Allow N/A</label><label className="checkbox-row"><input type="checkbox" name="requires_comment_on_fail"/>Require comment when deficient</label></div><div className="form-actions"><button className="primary-button small" type="submit">Add item</button></div></form></details>
        </section>)}
      </section>

      <section className="form-card compact-card">
        <div className="form-card-heading"><div><span>Draft structure</span><h2>Add section</h2></div></div>
        <form action={createInspectionSection}><input type="hidden" name="template_id" value={template.id}/><input type="hidden" name="version_id" value={draft.id}/><div className="form-grid two"><label className="field"><span>Section title *</span><input name="title" required placeholder="e.g. Airway & Oxygen"/></label><label className="field"><span>Order</span><input name="sort_order" type="number" step="10" defaultValue={((sections.at(-1)?.sort_order ?? 0) + 10)}/></label></div><div className="form-actions"><button className="primary-button small" type="submit">Add section</button></div></form>
      </section>
    </>}
  </>
}
