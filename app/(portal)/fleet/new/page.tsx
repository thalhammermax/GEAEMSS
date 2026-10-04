import type { Metadata } from 'next'
import Link from 'next/link'
import { createClient } from '@/lib/supabase/server'
import { PageHeader } from '@/components/page-header'
import { CustomFieldInputs } from '@/components/custom-field-inputs'
import { builtinFieldMap, fetchFieldDefinitions, isEnabled, isRequired } from '@/lib/record-fields'
import { createVehicle } from '../actions'
import { getModuleStates } from '@/lib/modules'

export const metadata: Metadata = { title: 'Add Vehicle' }
type Props = { searchParams: Promise<{ error?: string }> }

export default async function NewVehiclePage({ searchParams }: Props) {
  const { error } = await searchParams
  const supabase = await createClient()
  const moduleStates = await getModuleStates(supabase)
  const [{ data: agencies }, { data: types }, { data: statuses }, fieldResult] = await Promise.all([
    supabase.from('agencies').select('id, name').eq('active', true).order('name'),
    supabase.from('vehicle_types').select('id, name').eq('active', true).order('sort_order'),
    supabase.from('vehicle_statuses').select('id, name, code').eq('active', true).order('sort_order'),
    fetchFieldDefinitions(supabase, 'vehicle'),
  ])
  const defaultStatus = statuses?.find((s) => s.code === 'IN_SERVICE')?.id ?? ''
  const map = builtinFieldMap(fieldResult.fields)
  const custom = fieldResult.fields.filter((field) => field.source_type === 'custom')
  const req = (key: string, fallback = false) => isRequired(map, key, fallback)

  return <>
    <PageHeader eyebrow="Fleet" title="Add Vehicle" description="Create a vehicle record and assign it to a participating agency." />
    {error && <div className="banner danger"><div><strong>Vehicle was not saved</strong><span>{error}</span></div></div>}
    <form action={createVehicle} className="form-card">
      <div className="form-card-heading"><div><span>Vehicle</span><h2>Master record</h2></div></div>
      <div className="form-grid three">
        {isEnabled(map,'agency_id') && <label className="field"><span>Agency{req('agency_id',true) ? ' *' : ''}</span><select name="agency_id" required={req('agency_id',true)} defaultValue=""><option value="">Select agency</option>{agencies?.map((a) => <option key={a.id} value={a.id}>{a.name}</option>)}</select></label>}
        {isEnabled(map,'unit_number') && <label className="field"><span>Unit number{req('unit_number') ? ' *' : ''}</span><input name="unit_number" required={req('unit_number')} /></label>}
        {isEnabled(map,'fleet_number') && <label className="field"><span>Fleet number{req('fleet_number') ? ' *' : ''}</span><input name="fleet_number" required={req('fleet_number')} /></label>}
        {isEnabled(map,'vehicle_type_id') && <label className="field"><span>Vehicle type{req('vehicle_type_id') ? ' *' : ''}</span><select name="vehicle_type_id" required={req('vehicle_type_id')} defaultValue=""><option value="">Select type</option>{types?.map((t) => <option key={t.id} value={t.id}>{t.name}</option>)}</select></label>}
        {isEnabled(map,'vehicle_status_id') && <label className="field"><span>Vehicle status{req('vehicle_status_id') ? ' *' : ''}</span><select name="vehicle_status_id" required={req('vehicle_status_id')} defaultValue={defaultStatus}><option value="">Select status</option>{statuses?.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}</select></label>}
        {isEnabled(map,'vin') && <label className="field"><span>VIN{req('vin') ? ' *' : ''}</span><input name="vin" required={req('vin')} /></label>}
        {isEnabled(map,'year') && <label className="field"><span>Year{req('year') ? ' *' : ''}</span><input name="year" type="number" min="1900" max="2200" required={req('year')} /></label>}
        {isEnabled(map,'make') && <label className="field"><span>Make{req('make') ? ' *' : ''}</span><input name="make" required={req('make')} /></label>}
        {isEnabled(map,'model') && <label className="field"><span>Model{req('model') ? ' *' : ''}</span><input name="model" required={req('model')} /></label>}
        {isEnabled(map,'license_plate') && <label className="field"><span>License plate{req('license_plate') ? ' *' : ''}</span><input name="license_plate" required={req('license_plate')} /></label>}
        {isEnabled(map,'license_plate_state') && <label className="field"><span>Plate state{req('license_plate_state') ? ' *' : ''}</span><input name="license_plate_state" required={req('license_plate_state')} /></label>}
        {isEnabled(map,'in_service_date') && <label className="field"><span>In-service date{req('in_service_date') ? ' *' : ''}</span><input name="in_service_date" type="date" required={req('in_service_date')} /></label>}
        {isEnabled(map,'retired_date') && <label className="field"><span>Retired date{req('retired_date') ? ' *' : ''}</span><input name="retired_date" type="date" required={req('retired_date')} /></label>}
      </div>
      {isEnabled(map,'notes') && <label className="field"><span>Notes{req('notes') ? ' *' : ''}</span><textarea name="notes" rows={3} required={req('notes')} /></label>}
      {moduleStates.narcotics && <><div className="form-section-divider"><span>Narcotics Management</span></div><label className="checkbox-field"><input type="checkbox" name="narcotics_count_required"/><span>Require a signed daily narcotics count for this apparatus</span></label></>}
      <CustomFieldInputs fields={custom} />
      <div className="form-actions"><Link className="secondary-button button-link" href="/fleet">Cancel</Link><button className="primary-button" type="submit">Create vehicle</button></div>
    </form>
  </>
}
