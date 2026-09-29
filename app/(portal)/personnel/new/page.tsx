import type { Metadata } from 'next'
import Link from 'next/link'
import { createClient } from '@/lib/supabase/server'
import { PageHeader } from '@/components/page-header'
import { CustomFieldInputs } from '@/components/custom-field-inputs'
import { builtinFieldMap, fetchFieldDefinitions, isEnabled, isRequired } from '@/lib/record-fields'
import { createProvider } from '../actions'

export const metadata: Metadata = { title: 'Add Provider' }
type Props = { searchParams: Promise<{ error?: string }> }

export default async function NewProviderPage({ searchParams }: Props) {
  const { error } = await searchParams
  const supabase = await createClient()
  const [{ data: agencies }, { data: levels }, { data: statuses }, fieldResult] = await Promise.all([
    supabase.from('agencies').select('id, name').eq('active', true).order('name'),
    supabase.from('provider_levels').select('id, name').eq('active', true).order('sort_order'),
    supabase.from('provider_statuses').select('id, name, code').eq('active', true).order('name'),
    fetchFieldDefinitions(supabase, 'provider'),
  ])
  const defaultStatus = statuses?.find((s) => s.code === 'ACTIVE')?.id ?? ''
  const map = builtinFieldMap(fieldResult.fields)
  const custom = fieldResult.fields.filter((field) => field.source_type === 'custom')
  const req = (key: string, fallback = false) => isRequired(map, key, fallback)

  return <>
    <PageHeader title="Add Provider" description="Create one system-wide provider record and assign the primary agency." />
    {error && <div className="banner danger"><div><strong>Provider was not saved</strong><span>{error}</span></div></div>}
    <form action={createProvider} className="form-card">
      <div className="form-card-heading"><div><span>Provider</span><h2>Identity and system information</h2></div></div>
      <div className="form-grid three">
        {isEnabled(map,'first_name') && <label className="field"><span>First name{req('first_name',true) ? ' *' : ''}</span><input name="first_name" required={req('first_name',true)} /></label>}
        {isEnabled(map,'middle_name') && <label className="field"><span>Middle name{req('middle_name') ? ' *' : ''}</span><input name="middle_name" required={req('middle_name')} /></label>}
        {isEnabled(map,'last_name') && <label className="field"><span>Last name{req('last_name',true) ? ' *' : ''}</span><input name="last_name" required={req('last_name',true)} /></label>}
        {isEnabled(map,'preferred_name') && <label className="field"><span>Preferred name{req('preferred_name') ? ' *' : ''}</span><input name="preferred_name" required={req('preferred_name')} /></label>}
        {isEnabled(map,'provider_number') && <label className="field"><span>System provider ID{req('provider_number') ? ' *' : ''}</span><input name="provider_number" required={req('provider_number')} /></label>}
        {isEnabled(map,'system_entry_date') && <label className="field"><span>System entry date{req('system_entry_date') ? ' *' : ''}</span><input name="system_entry_date" type="date" required={req('system_entry_date')} /></label>}
        {isEnabled(map,'provider_level_id') && <label className="field"><span>Provider level{req('provider_level_id') ? ' *' : ''}</span><select name="provider_level_id" defaultValue="" required={req('provider_level_id')}><option value="">Select level</option>{levels?.map((l) => <option key={l.id} value={l.id}>{l.name}</option>)}</select></label>}
        {isEnabled(map,'provider_status_id') && <label className="field"><span>System status{req('provider_status_id') ? ' *' : ''}</span><select name="provider_status_id" defaultValue={defaultStatus} required={req('provider_status_id')}><option value="">Select status</option>{statuses?.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}</select></label>}
        {isEnabled(map,'email') && <label className="field"><span>Email{req('email') ? ' *' : ''}</span><input name="email" type="email" required={req('email')} /></label>}
        {isEnabled(map,'phone') && <label className="field"><span>Phone{req('phone') ? ' *' : ''}</span><input name="phone" type="tel" required={req('phone')} /></label>}
      </div>
      {isEnabled(map,'notes') && <label className="field"><span>Notes{req('notes') ? ' *' : ''}</span><textarea name="notes" rows={3} required={req('notes')} /></label>}

      <CustomFieldInputs fields={custom} />

      <div className="form-section-divider"><span>Portal account</span></div>
      <div className="account-invite-option">
        <label className="checkbox-field"><input name="send_account_invite" type="checkbox" /><span><strong>Email this provider a portal account setup link</strong><small>Optional and off by default. The provider's email address will be their login username. You can send the invitation later from Administration → User Management.</small></span></label>
      </div>

      <div className="form-section-divider"><span>Primary agency affiliation</span></div>
      <div className="form-grid three">
        <label className="field"><span>Agency *</span><select name="agency_id" required defaultValue=""><option value="" disabled>Select agency</option>{agencies?.map((a) => <option key={a.id} value={a.id}>{a.name}</option>)}</select></label>
        <label className="field"><span>Agency employee ID</span><input name="employee_id" /></label>
        <label className="field"><span>Agency provider level</span><select name="agency_provider_level_id" defaultValue=""><option value="">Same / unspecified</option>{levels?.map((l) => <option key={l.id} value={l.id}>{l.name}</option>)}</select></label>
        <label className="field"><span>Agency start date</span><input name="start_date" type="date" /></label>
      </div>
      <div className="form-actions"><Link className="secondary-button button-link" href="/personnel">Cancel</Link><button className="primary-button" type="submit">Create provider</button></div>
    </form>
  </>
}
