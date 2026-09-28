import type { Metadata } from 'next'
import Link from 'next/link'
import { notFound } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { PageHeader } from '@/components/page-header'
import { CustomFieldInputs } from '@/components/custom-field-inputs'
import { builtinFieldMap, fetchCustomFieldValues, fetchFieldDefinitions, isEnabled, isRequired } from '@/lib/record-fields'
import { updateProvider } from '../../actions'

export const metadata: Metadata = { title: 'Edit Provider' }
type Props = { params: Promise<{ id: string }>; searchParams: Promise<{ error?: string }> }

export default async function EditProviderPage({ params, searchParams }: Props) {
  const { id } = await params
  const { error: formError } = await searchParams
  const supabase = await createClient()
  const [{ data: provider, error }, { data: levels }, { data: statuses }, fieldResult, valueResult] = await Promise.all([
    supabase.from('providers').select('*').eq('id', id).maybeSingle(),
    supabase.from('provider_levels').select('id, name').eq('active', true).order('sort_order'),
    supabase.from('provider_statuses').select('id, name').eq('active', true).order('name'),
    fetchFieldDefinitions(supabase, 'provider'),
    fetchCustomFieldValues(supabase, id),
  ])
  if (error || !provider) notFound()
  const map = builtinFieldMap(fieldResult.fields)
  const custom = fieldResult.fields.filter((field) => field.source_type === 'custom')
  const req = (key: string, fallback = false) => isRequired(map, key, fallback)

  return <>
    <PageHeader eyebrow="Personnel" title={`Edit ${provider.first_name} ${provider.last_name}`} description="Update the system-wide provider record." />
    {formError && <div className="banner danger"><div><strong>Provider was not saved</strong><span>{formError}</span></div></div>}
    <form action={updateProvider} className="form-card">
      <input type="hidden" name="id" value={provider.id} />
      <div className="form-grid three">
        {isEnabled(map,'first_name') && <label className="field"><span>First name{req('first_name',true) ? ' *' : ''}</span><input name="first_name" defaultValue={provider.first_name} required={req('first_name',true)} /></label>}
        {isEnabled(map,'middle_name') && <label className="field"><span>Middle name{req('middle_name') ? ' *' : ''}</span><input name="middle_name" defaultValue={provider.middle_name ?? ''} required={req('middle_name')} /></label>}
        {isEnabled(map,'last_name') && <label className="field"><span>Last name{req('last_name',true) ? ' *' : ''}</span><input name="last_name" defaultValue={provider.last_name} required={req('last_name',true)} /></label>}
        {isEnabled(map,'preferred_name') && <label className="field"><span>Preferred name{req('preferred_name') ? ' *' : ''}</span><input name="preferred_name" defaultValue={provider.preferred_name ?? ''} required={req('preferred_name')} /></label>}
        {isEnabled(map,'provider_number') && <label className="field"><span>System provider ID{req('provider_number') ? ' *' : ''}</span><input name="provider_number" defaultValue={provider.provider_number ?? ''} required={req('provider_number')} /></label>}
        {isEnabled(map,'system_entry_date') && <label className="field"><span>System entry date{req('system_entry_date') ? ' *' : ''}</span><input name="system_entry_date" type="date" defaultValue={provider.system_entry_date ?? ''} required={req('system_entry_date')} /></label>}
        {isEnabled(map,'provider_level_id') && <label className="field"><span>Provider level{req('provider_level_id') ? ' *' : ''}</span><select name="provider_level_id" defaultValue={provider.provider_level_id ?? ''} required={req('provider_level_id')}><option value="">Unassigned</option>{levels?.map((l) => <option key={l.id} value={l.id}>{l.name}</option>)}</select></label>}
        {isEnabled(map,'provider_status_id') && <label className="field"><span>System status{req('provider_status_id') ? ' *' : ''}</span><select name="provider_status_id" defaultValue={provider.provider_status_id ?? ''} required={req('provider_status_id')}><option value="">Unassigned</option>{statuses?.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}</select></label>}
        {isEnabled(map,'email') && <label className="field"><span>Email{req('email') ? ' *' : ''}</span><input name="email" type="email" defaultValue={provider.email ?? ''} required={req('email')} /></label>}
        {isEnabled(map,'phone') && <label className="field"><span>Phone{req('phone') ? ' *' : ''}</span><input name="phone" type="tel" defaultValue={provider.phone ?? ''} required={req('phone')} /></label>}
      </div>
      {isEnabled(map,'notes') && <label className="field"><span>Notes{req('notes') ? ' *' : ''}</span><textarea name="notes" rows={4} defaultValue={provider.notes ?? ''} required={req('notes')} /></label>}
      <CustomFieldInputs fields={custom} values={valueResult.values} />
      <div className="form-actions"><Link className="secondary-button button-link" href={`/personnel/${provider.id}`}>Cancel</Link><button className="primary-button" type="submit">Save changes</button></div>
    </form>
  </>
}
