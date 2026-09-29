import type { Metadata } from 'next'
import Link from 'next/link'
import { notFound } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { PageHeader } from '@/components/page-header'
import { CustomFieldInputs } from '@/components/custom-field-inputs'
import { builtinFieldMap, fetchCustomFieldValues, fetchFieldDefinitions, isEnabled, isRequired } from '@/lib/record-fields'
import { setVehicleActive, updateVehicle } from '../actions'

export const metadata: Metadata = { title: 'Vehicle' }
type Props = { params: Promise<{ id: string }>; searchParams: Promise<{ error?: string; saved?: string }> }

export default async function VehiclePage({ params, searchParams }: Props) {
  const { id } = await params
  const qs = await searchParams
  const supabase = await createClient()
  const [{ data: vehicle, error }, { data: agencies }, { data: types }, { data: statuses }, { data: narcoticsTemplates }, fieldResult, valueResult] = await Promise.all([
    supabase.from('vehicles').select('*, agencies(name, short_name), vehicle_types(name), vehicle_statuses(name)').eq('id', id).maybeSingle(),
    supabase.from('agencies').select('id, name').eq('active', true).order('name'),
    supabase.from('vehicle_types').select('id, name').eq('active', true).order('sort_order'),
    supabase.from('vehicle_statuses').select('id, name').eq('active', true).order('sort_order'),
    supabase.from('narcotics_count_templates').select('id, name, scope_type, agency_id').eq('active', true).order('name'),
    fetchFieldDefinitions(supabase, 'vehicle'),
    fetchCustomFieldValues(supabase, id),
  ])
  if (error || !vehicle) notFound()

  const map = builtinFieldMap(fieldResult.fields)
  const custom = fieldResult.fields.filter((field) => field.source_type === 'custom')
  const req = (key: string, fallback = false) => isRequired(map, key, fallback)
  const title = vehicle.unit_number || vehicle.fleet_number || [vehicle.year, vehicle.make, vehicle.model].filter(Boolean).join(' ') || 'Vehicle'

  return <>
    <PageHeader eyebrow="Fleet" title={title} description={`${vehicle.agencies?.name ?? 'Agency'} · ${vehicle.vehicle_types?.name ?? 'Vehicle record'}`} />
    {qs.saved && <div className="banner success"><div><strong>Saved</strong><span>Vehicle information was updated.</span></div></div>}
    {qs.error && <div className="banner danger"><div><strong>Unable to save</strong><span>{qs.error}</span></div></div>}

    <div className="dashboard-columns detail-columns">
      <form action={updateVehicle} className="form-card">
        <input type="hidden" name="id" value={vehicle.id} />
        <div className="form-card-heading"><div><span>Vehicle</span><h2>Master record</h2></div><span className={`pill ${vehicle.active ? 'green' : ''}`}>{vehicle.active ? 'Active' : 'Inactive'}</span></div>
        <div className="form-grid three">
          {isEnabled(map,'agency_id') && <label className="field"><span>Agency{req('agency_id',true) ? ' *' : ''}</span><select name="agency_id" required={req('agency_id',true)} defaultValue={vehicle.agency_id}><option value="">Select agency</option>{agencies?.map((a) => <option key={a.id} value={a.id}>{a.name}</option>)}</select></label>}
          {isEnabled(map,'unit_number') && <label className="field"><span>Unit number{req('unit_number') ? ' *' : ''}</span><input name="unit_number" defaultValue={vehicle.unit_number ?? ''} required={req('unit_number')} /></label>}
          {isEnabled(map,'fleet_number') && <label className="field"><span>Fleet number{req('fleet_number') ? ' *' : ''}</span><input name="fleet_number" defaultValue={vehicle.fleet_number ?? ''} required={req('fleet_number')} /></label>}
          {isEnabled(map,'vehicle_type_id') && <label className="field"><span>Vehicle type{req('vehicle_type_id') ? ' *' : ''}</span><select name="vehicle_type_id" required={req('vehicle_type_id')} defaultValue={vehicle.vehicle_type_id ?? ''}><option value="">Select type</option>{types?.map((t) => <option key={t.id} value={t.id}>{t.name}</option>)}</select></label>}
          {isEnabled(map,'vehicle_status_id') && <label className="field"><span>Vehicle status{req('vehicle_status_id') ? ' *' : ''}</span><select name="vehicle_status_id" required={req('vehicle_status_id')} defaultValue={vehicle.vehicle_status_id ?? ''}><option value="">Select status</option>{statuses?.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}</select></label>}
          {isEnabled(map,'vin') && <label className="field"><span>VIN{req('vin') ? ' *' : ''}</span><input name="vin" defaultValue={vehicle.vin ?? ''} required={req('vin')} /></label>}
          {isEnabled(map,'year') && <label className="field"><span>Year{req('year') ? ' *' : ''}</span><input name="year" type="number" min="1900" max="2200" defaultValue={vehicle.year ?? ''} required={req('year')} /></label>}
          {isEnabled(map,'make') && <label className="field"><span>Make{req('make') ? ' *' : ''}</span><input name="make" defaultValue={vehicle.make ?? ''} required={req('make')} /></label>}
          {isEnabled(map,'model') && <label className="field"><span>Model{req('model') ? ' *' : ''}</span><input name="model" defaultValue={vehicle.model ?? ''} required={req('model')} /></label>}
          {isEnabled(map,'license_plate') && <label className="field"><span>License plate{req('license_plate') ? ' *' : ''}</span><input name="license_plate" defaultValue={vehicle.license_plate ?? ''} required={req('license_plate')} /></label>}
          {isEnabled(map,'license_plate_state') && <label className="field"><span>Plate state{req('license_plate_state') ? ' *' : ''}</span><input name="license_plate_state" defaultValue={vehicle.license_plate_state ?? ''} required={req('license_plate_state')} /></label>}
          {isEnabled(map,'in_service_date') && <label className="field"><span>In-service date{req('in_service_date') ? ' *' : ''}</span><input name="in_service_date" type="date" defaultValue={vehicle.in_service_date ?? ''} required={req('in_service_date')} /></label>}
          {isEnabled(map,'retired_date') && <label className="field"><span>Retired date{req('retired_date') ? ' *' : ''}</span><input name="retired_date" type="date" defaultValue={vehicle.retired_date ?? ''} required={req('retired_date')} /></label>}
        </div>
        {isEnabled(map,'notes') && <label className="field"><span>Notes{req('notes') ? ' *' : ''}</span><textarea name="notes" rows={3} defaultValue={vehicle.notes ?? ''} required={req('notes')} /></label>}
        <div className="form-section-divider"><span>Narcotics Management</span></div>
        <div className="form-grid"><label className="checkbox-field"><input type="checkbox" name="narcotics_count_required" defaultChecked={vehicle.narcotics_count_required}/><span>Require a signed daily narcotics count for this apparatus</span></label><label className="field"><span>Count template override</span><select name="narcotics_template_id" defaultValue={vehicle.narcotics_template_id ?? ''}><option value="">Use agency default</option>{(narcoticsTemplates ?? []).filter((t:any) => t.scope_type === 'system' || t.agency_id === vehicle.agency_id).map((t:any) => <option key={t.id} value={t.id}>{t.name}{t.scope_type === 'system' ? ' · System' : ''}</option>)}</select></label></div>
        <CustomFieldInputs fields={custom} values={valueResult.values} />
        <div className="form-actions"><button className="primary-button" type="submit">Save changes</button></div>
      </form>

      <section className="panel">
        <div className="panel-heading"><h3>Record status</h3><span>Archive without deleting history</span></div>
        <p className="panel-copy">Inactivating a vehicle keeps licensing, inspection and audit history intact while removing it from normal active-fleet workflows.</p>
        {vehicle.active && <p><Link className="primary-button small button-link" href={`/inspections/new?vehicle=${vehicle.id}`}>Start inspection</Link></p>}
        <form action={setVehicleActive}>
          <input type="hidden" name="id" value={vehicle.id} />
          <input type="hidden" name="active" value={vehicle.active ? 'false' : 'true'} />
          <button className={vehicle.active ? 'secondary-button danger-outline' : 'primary-button'} type="submit">{vehicle.active ? 'Mark vehicle inactive' : 'Reactivate vehicle'}</button>
        </form>
      </section>
    </div>
  </>
}
