import type { Metadata } from 'next'
import Link from 'next/link'
import { PageHeader } from '@/components/page-header'
import { CustomFieldInputs } from '@/components/custom-field-inputs'
import { createClient } from '@/lib/supabase/server'
import { builtinFieldMap, fetchFieldDefinitions, isEnabled, isRequired } from '@/lib/record-fields'
import { createAgency } from '../actions'

export const metadata: Metadata = { title: 'Add Agency' }
type Props = { searchParams: Promise<{ error?: string }> }

export default async function NewAgencyPage({ searchParams }: Props) {
  const { error } = await searchParams
  const supabase = await createClient()
  const fieldResult = await fetchFieldDefinitions(supabase, 'agency')
  const map = builtinFieldMap(fieldResult.fields)
  const custom = fieldResult.fields.filter((field) => field.source_type === 'custom')
  const req = (key: string, fallback = false) => isRequired(map, key, fallback)

  return <>
    <PageHeader title="Add Agency" description="Create a participating agency in the GEAEMS System registry." />
    {error && <div className="banner danger"><div><strong>Agency was not saved</strong><span>{error}</span></div></div>}
    <form action={createAgency} className="form-card">
      <div className="form-grid two">
        {isEnabled(map,'name') && <label className="field"><span>Agency name{req('name',true) ? ' *' : ''}</span><input name="name" required={req('name',true)} placeholder="Elgin Fire Department" /></label>}
        {isEnabled(map,'short_name') && <label className="field"><span>Abbreviation{req('short_name') ? ' *' : ''}</span><input name="short_name" required={req('short_name')} placeholder="EFD" maxLength={30} /></label>}
        {isEnabled(map,'address') && <label className="field span-two"><span>Agency address{req('address') ? ' *' : ''}</span><textarea name="address" rows={2} required={req('address')} placeholder="123 Main St, Elgin, IL 60120" /><small>This is also used as the Agency Headquarters location on inspections when selected.</small></label>}
      </div>
      <CustomFieldInputs fields={custom} />
      <div className="form-actions"><Link className="secondary-button button-link" href="/administration/agencies">Cancel</Link><button className="primary-button" type="submit">Create agency</button></div>
    </form>
  </>
}
