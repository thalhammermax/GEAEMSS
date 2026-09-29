import type { Metadata } from 'next'
import Link from 'next/link'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { PageHeader } from '@/components/page-header'
import { saveNarcoticsAgencySettings } from '../actions'

export const metadata: Metadata = { title: 'Narcotics Settings' }
type Props = { searchParams: Promise<{ error?: string; notice?: string }> }

export default async function NarcoticsSettingsPage({ searchParams }: Props) {
  const qs = await searchParams
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')
  const [{ data: roles }, { data: agencies }, { data: settings }, { data: templates }, { data: access }] = await Promise.all([
    supabase.from('user_roles').select('role').eq('user_id', user.id),
    supabase.from('agencies').select('id, name, short_name').eq('active', true).order('name'),
    supabase.from('narcotics_agency_settings').select('*'),
    supabase.from('narcotics_count_templates').select('id, name, scope_type, agency_id, active').eq('active', true).order('name'),
    supabase.from('user_agency_access').select('agency_id, can_manage_narcotics').eq('user_id', user.id),
  ])
  const roleNames = new Set((roles ?? []).map((r:any) => r.role))
  const isSystemAdmin = roleNames.has('system_admin')
  const isAgencyAdmin = roleNames.has('agency_admin')
  if (!isSystemAdmin && !isAgencyAdmin) redirect('/narcotics')
  const accessMap = new Map<string, any>((access ?? []).map((a:any) => [a.agency_id, a]))
  const settingMap = new Map<string, any>((settings ?? []).map((s:any) => [s.agency_id, s]))
  const manageableAgencies = (agencies ?? []).filter((a:any) => isSystemAdmin || accessMap.get(a.id)?.can_manage_narcotics)

  return <>
    <PageHeader eyebrow="Narcotics" title="Templates & settings" description="Configure daily count templates, due reporting, and agency defaults." action={<Link className="primary-button small button-link" href="/narcotics/templates/new">New count template</Link>} />
    {qs.notice && <div className="banner success"><div><strong>Saved</strong><span>{qs.notice}</span></div></div>}
    {qs.error && <div className="banner danger"><div><strong>Unable to save</strong><span>{qs.error}</span></div></div>}
    <section className="section-block"><div className="section-title"><div><span>Inventory</span><h2>Count templates</h2></div><div className="section-badge">{templates?.length ?? 0} active</div></div><div className="table-card">{(templates ?? []).length === 0 ? <div className="empty-state compact"><strong>No templates yet</strong><span>Create the list of controlled substances and expected quantities that an apparatus should carry.</span></div> : <table><thead><tr><th>Template</th><th>Scope</th><th></th></tr></thead><tbody>{(templates ?? []).map((t:any) => { const agency = (agencies ?? []).find((a:any) => a.id === t.agency_id); const canEdit = isSystemAdmin || (t.scope_type === 'agency' && accessMap.get(t.agency_id)?.can_manage_narcotics); return <tr key={t.id}><td><strong>{t.name}</strong></td><td>{t.scope_type === 'system' ? 'GEAEMS System' : agency?.name || 'Agency'}</td><td className="table-action">{canEdit ? <Link href={`/narcotics/templates/${t.id}`}>Edit</Link> : <span className="muted-code">System template</span>}</td></tr>})}</tbody></table>}</div></section>
    <section className="section-block"><div className="section-title"><div><span>Agency</span><h2>Daily count reporting</h2></div></div><div className="agency-settings-grid">{manageableAgencies.map((agency:any) => { const setting:any = settingMap.get(agency.id) || {}; const available = (templates ?? []).filter((t:any) => t.scope_type === 'system' || t.agency_id === agency.id); return <form action={saveNarcoticsAgencySettings} className="form-card compact-card" key={agency.id}><input type="hidden" name="agency_id" value={agency.id}/><div className="form-card-heading"><div><span>Agency settings</span><h2>{agency.name}</h2></div></div><div className="form-grid two"><label className="field"><span>Default count template</span><select name="default_template_id" defaultValue={setting.default_template_id || ''}><option value="">No default template</option>{available.map((t:any) => <option key={t.id} value={t.id}>{t.name}{t.scope_type === 'system' ? ' · System' : ''}</option>)}</select></label><label className="field"><span>Daily report hour</span><select name="report_hour" defaultValue={String(setting.report_hour ?? 8)}>{Array.from({length:24},(_,hour) => <option key={hour} value={hour}>{new Intl.DateTimeFormat('en-US',{hour:'numeric',hour12:true,timeZone:'UTC'}).format(new Date(Date.UTC(2020,0,1,hour)))}</option>)}</select></label><label className="field"><span>Time zone</span><input name="timezone" defaultValue={setting.timezone || 'America/Chicago'}/></label><label className="field span-two"><span>Electronic signature attestation</span><textarea name="signature_attestation" rows={3} defaultValue={setting.signature_attestation || 'I attest that I personally performed this narcotics inventory count and that the quantities entered are accurate to the best of my knowledge.'}/></label></div><div className="inline-options"><label className="checkbox-row"><input type="checkbox" name="enabled" defaultChecked={setting.enabled !== false}/>Enable narcotics module for agency</label><label className="checkbox-row"><input type="checkbox" name="send_incomplete_report" defaultChecked={setting.send_incomplete_report !== false}/>Email incomplete-count report</label></div><div className="form-actions"><button className="primary-button small" type="submit">Save agency settings</button></div></form>})}</div></section>
  </>
}
