import type { Metadata } from 'next'
import Link from 'next/link'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { PageHeader } from '@/components/page-header'
import { saveNarcoticsAgencySettings, saveNarcoticsVehicleTypeTemplate } from '../actions'

export const metadata: Metadata = { title: 'Narcotics Settings' }
type Props = { searchParams: Promise<{ error?: string; notice?: string }> }

export default async function NarcoticsSettingsPage({ searchParams }: Props) {
  const qs = await searchParams
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const [
    { data: roles },
    { data: agencies },
    { data: settings },
    { data: templates },
    { data: access },
    { data: vehicleTypes },
  ] = await Promise.all([
    supabase.from('user_roles').select('role').eq('user_id', user.id),
    supabase.from('agencies').select('id, name, short_name').eq('active', true).order('name'),
    supabase.from('narcotics_agency_settings').select('*'),
    supabase.from('narcotics_count_templates').select('id, name, scope_type, agency_id, active').eq('active', true).order('name'),
    supabase.from('user_agency_access').select('agency_id, can_manage_narcotics').eq('user_id', user.id),
    supabase.from('vehicle_types').select('id, code, name, narcotics_template_id').eq('active', true).order('sort_order').order('name'),
  ])

  const roleNames = new Set((roles ?? []).map((r: any) => r.role))
  const isSystemAdmin = roleNames.has('system_admin')
  const isAgencyAdmin = roleNames.has('agency_admin')
  if (!isSystemAdmin && !isAgencyAdmin) redirect('/narcotics')

  const accessMap = new Map<string, any>((access ?? []).map((a: any) => [a.agency_id, a]))
  const settingMap = new Map<string, any>((settings ?? []).map((s: any) => [s.agency_id, s]))
  const manageableAgencies = (agencies ?? []).filter((a: any) => isSystemAdmin || accessMap.get(a.id)?.can_manage_narcotics)
  const systemTemplates = (templates ?? []).filter((t: any) => t.scope_type === 'system')

  return <>
    <PageHeader
      eyebrow="Narcotics"
      title="Forms & settings"
      description="Assign daily count forms by vehicle type and configure agency reporting and signature settings."
      action={isSystemAdmin ? <Link className="primary-button small button-link" href="/narcotics/templates/new">New count form</Link> : undefined}
    />
    {qs.notice && <div className="banner success"><div><strong>Saved</strong><span>{qs.notice}</span></div></div>}
    {qs.error && <div className="banner danger"><div><strong>Unable to save</strong><span>{qs.error}</span></div></div>}

    {isSystemAdmin && <section className="section-block">
      <div className="section-title"><div><span>Vehicle types</span><h2>Daily narcotics form assignment</h2></div><span className="section-badge">System controlled</span></div>
      <div className="banner info"><div><strong>Forms follow the vehicle type.</strong><span>There is no agency default form. Every apparatus automatically uses the form assigned to its current vehicle type.</span></div></div>
      <div className="table-card">
        {(vehicleTypes ?? []).length === 0 ? <div className="empty-state compact"><strong>No vehicle types found</strong></div> : <table>
          <thead><tr><th>Vehicle type</th><th>Daily narcotics form</th><th></th></tr></thead>
          <tbody>{(vehicleTypes ?? []).map((type: any) => <tr key={type.id}>
            <td><strong>{type.name}</strong><div className="muted-code">{type.code}</div></td>
            <td colSpan={2}>
              <form action={saveNarcoticsVehicleTypeTemplate} className="inline-form">
                <input type="hidden" name="vehicle_type_id" value={type.id}/>
                <select name="narcotics_template_id" defaultValue={type.narcotics_template_id || ''}>
                  <option value="">No daily narcotics form</option>
                  {systemTemplates.map((template: any) => <option key={template.id} value={template.id}>{template.name}</option>)}
                </select>
                <button className="secondary-button small" type="submit">Save</button>
              </form>
            </td>
          </tr>)}</tbody>
        </table>}
      </div>
    </section>}

    <section className="section-block">
      <div className="section-title"><div><span>Inventory</span><h2>Count forms</h2></div><div className="section-badge">{systemTemplates.length} system forms</div></div>
      <div className="table-card">{systemTemplates.length === 0 ? <div className="empty-state compact"><strong>No system forms yet</strong><span>Create the controlled-substance inventory form, then assign it to one or more vehicle types above.</span></div> : <table>
        <thead><tr><th>Form</th><th>Scope</th><th></th></tr></thead>
        <tbody>{systemTemplates.map((t: any) => <tr key={t.id}><td><strong>{t.name}</strong></td><td>GEAEMS System</td><td className="table-action">{isSystemAdmin ? <Link href={`/narcotics/templates/${t.id}`}>Edit</Link> : <span className="muted-code">System form</span>}</td></tr>)}</tbody>
      </table>}</div>
    </section>

    <section className="section-block">
      <div className="section-title"><div><span>Agency</span><h2>Daily count reporting</h2></div></div>
      <div className="agency-settings-grid">{manageableAgencies.map((agency: any) => {
        const setting: any = settingMap.get(agency.id) || {}
        return <form action={saveNarcoticsAgencySettings} className="form-card compact-card" key={agency.id}>
          <input type="hidden" name="agency_id" value={agency.id}/>
          <div className="form-card-heading"><div><span>Agency settings</span><h2>{agency.name}</h2></div></div>
          <div className="form-grid two">
            <label className="field"><span>Daily report hour</span><select name="report_hour" defaultValue={String(setting.report_hour ?? 8)}>{Array.from({length:24},(_,hour) => <option key={hour} value={hour}>{new Intl.DateTimeFormat('en-US',{hour:'numeric',hour12:true,timeZone:'UTC'}).format(new Date(Date.UTC(2020,0,1,hour)))}</option>)}</select></label>
            <label className="field"><span>Time zone</span><input name="timezone" defaultValue={setting.timezone || 'America/Chicago'}/></label>
            <label className="field span-two"><span>Electronic signature attestation</span><textarea name="signature_attestation" rows={3} defaultValue={setting.signature_attestation || 'I attest that I personally performed this narcotics inventory count and that the quantities entered are accurate to the best of my knowledge.'}/></label>
          </div>
          <div className="inline-options"><label className="checkbox-row"><input type="checkbox" name="enabled" defaultChecked={setting.enabled !== false}/>Enable narcotics module for agency</label><label className="checkbox-row"><input type="checkbox" name="send_incomplete_report" defaultChecked={setting.send_incomplete_report !== false}/>Email incomplete-count report</label></div>
          <div className="form-actions"><button className="primary-button small" type="submit">Save agency settings</button></div>
        </form>
      })}</div>
    </section>
  </>
}
