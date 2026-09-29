import type { Metadata } from 'next'
import Link from 'next/link'
import { notFound, redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { PageHeader } from '@/components/page-header'
import { formatQuantity } from '@/lib/narcotics'
import { addNarcoticsTemplateItem, deleteNarcoticsTemplateItem, updateNarcoticsTemplate } from '../../actions'

export const metadata: Metadata = { title: 'Narcotics Template' }
type Props = { params: Promise<{ id:string }>; searchParams: Promise<{ error?:string; notice?:string }> }
export default async function TemplatePage({ params, searchParams }: Props) {
  const { id } = await params; const qs = await searchParams; const supabase = await createClient()
  const [{ data: template }, { data: items }] = await Promise.all([
    supabase.from('narcotics_count_templates').select('*, agencies(name)').eq('id', id).maybeSingle(),
    supabase.from('narcotics_count_template_items').select('*').eq('template_id', id).order('sort_order').order('medication_name'),
  ])
  if (!template) notFound()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')
  const [{ data: roles }, { data: access }] = await Promise.all([
    supabase.from('user_roles').select('role').eq('user_id', user.id),
    supabase.from('user_agency_access').select('agency_id, can_manage_narcotics').eq('user_id', user.id),
  ])
  const roleNames = new Set((roles ?? []).map((r:any) => r.role))
  const canManage = roleNames.has('system_admin') || (template.scope_type === 'agency' && (access ?? []).some((a:any) => a.agency_id === template.agency_id && a.can_manage_narcotics))
  if (!canManage) redirect('/narcotics')
  return <><PageHeader eyebrow="Narcotics Template" title={template.name} description={template.scope_type === 'system' ? 'GEAEMS System template' : `Agency template`} action={<Link className="secondary-button button-link" href="/narcotics/settings">Back to settings</Link>}/>{qs.notice && <div className="banner success"><div><strong>Saved</strong><span>{qs.notice}</span></div></div>}{qs.error && <div className="banner danger"><div><strong>Unable to save</strong><span>{qs.error}</span></div></div>}<form action={updateNarcoticsTemplate} className="form-card compact-card"><input type="hidden" name="template_id" value={id}/><div className="form-grid"><label className="field"><span>Name</span><input name="name" defaultValue={template.name} required/></label><label className="checkbox-field"><input type="checkbox" name="active" defaultChecked={template.active}/><span>Template active</span></label><label className="field span-two"><span>Description</span><textarea name="description" rows={2} defaultValue={template.description || ''}/></label></div><div className="form-actions"><button className="secondary-button" type="submit">Save template</button></div></form><section className="section-block"><div className="section-title"><div><span>Daily inventory</span><h2>Controlled substances</h2></div><div className="section-badge">{items?.length ?? 0} items</div></div><div className="table-card">{(items ?? []).length === 0 ? <div className="empty-state compact"><strong>No count items yet</strong><span>Add each medication or controlled substance that should appear on the daily count.</span></div> : <table><thead><tr><th>Medication</th><th>Concentration</th><th>Expected</th><th>Schedule</th><th></th></tr></thead><tbody>{(items ?? []).map((item:any) => <tr key={item.id}><td><strong>{item.medication_name}</strong>{item.dosage_form && <div className="muted-code">{item.dosage_form}</div>}</td><td>{item.concentration || '—'}</td><td>{formatQuantity(item.expected_quantity)} {item.unit_label}</td><td>{item.controlled_substance_schedule || '—'}</td><td className="table-action"><form action={deleteNarcoticsTemplateItem}><input type="hidden" name="template_id" value={id}/><input type="hidden" name="item_id" value={item.id}/><button className="text-button" type="submit">Remove</button></form></td></tr>)}</tbody></table>}</div></section><form action={addNarcoticsTemplateItem} className="form-card"><input type="hidden" name="template_id" value={id}/><div className="form-card-heading"><div><span>Template item</span><h2>Add controlled substance</h2></div></div><div className="form-grid four"><label className="field"><span>Medication *</span><input name="medication_name" required/></label><label className="field"><span>Concentration</span><input name="concentration" placeholder="e.g. 10 mg/mL"/></label><label className="field"><span>Dosage form</span><input name="dosage_form" placeholder="Vial, syringe, etc."/></label><label className="field"><span>DEA schedule</span><input name="controlled_substance_schedule" placeholder="Optional"/></label><label className="field"><span>Expected quantity *</span><input name="expected_quantity" type="number" min="0" step="0.001" required/></label><label className="field"><span>Unit label</span><input name="unit_label" defaultValue="unit"/></label><label className="field"><span>Sort order</span><input name="sort_order" type="number" defaultValue="100"/></label></div><div className="form-actions"><button className="primary-button" type="submit">Add item</button></div></form></>
}
