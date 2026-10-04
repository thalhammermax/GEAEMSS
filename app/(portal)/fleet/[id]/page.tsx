import type { Metadata } from 'next'
import Link from 'next/link'
import { notFound } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { PageHeader } from '@/components/page-header'
import { CustomFieldInputs } from '@/components/custom-field-inputs'
import { builtinFieldMap, fetchCustomFieldValues, fetchFieldDefinitions, isEnabled, isRequired } from '@/lib/record-fields'
import { setVehicleActive, updateVehicle } from '../actions'
import { formatDate, titleCase } from '@/lib/format'
import { getModuleStates } from '@/lib/modules'

export const metadata: Metadata = { title: 'Vehicle' }
type Props = { params: Promise<{ id: string }>; searchParams: Promise<{ error?: string; saved?: string }> }

export default async function VehiclePage({ params, searchParams }: Props) {
  const { id } = await params
  const qs = await searchParams
  const supabase = await createClient()
  const moduleStates = await getModuleStates(supabase)
  const narcoticsEnabled = moduleStates.narcotics
  const [{ data: vehicle, error }, { data: agencies }, { data: types }, { data: statuses }, { data: narcoticsTemplates }, { data: completedInspections, error: inspectionHistoryError }, fieldResult, valueResult] = await Promise.all([
    supabase.from('vehicles').select('*, agencies(name, short_name, active), vehicle_types(name), vehicle_statuses(name)').eq('id', id).maybeSingle(),
    supabase.from('agencies').select('id, name, active').order('name'),
    supabase.from('vehicle_types').select('id, name, narcotics_template_id').eq('active', true).order('sort_order'),
    supabase.from('vehicle_statuses').select('id, name').eq('active', true).order('sort_order'),
    narcoticsEnabled ? supabase.from('narcotics_count_templates').select('id, name').eq('active', true).eq('scope_type', 'system').order('name') : Promise.resolve({ data: [] as any[] }),
    supabase.from('vehicle_inspections').select('id, inspection_date, workflow_status, result, next_due_date, inspector_name, submitted_at, inspection_types(name), inspection_form_versions(version_number, inspection_form_templates(name))').eq('vehicle_id', id).eq('workflow_status', 'submitted').order('inspection_date', { ascending: false }).order('submitted_at', { ascending: false }).limit(250),
    fetchFieldDefinitions(supabase, 'vehicle'),
    fetchCustomFieldValues(supabase, id),
  ])
  if (error || !vehicle) notFound()

  const map = builtinFieldMap(fieldResult.fields)
  const custom = fieldResult.fields.filter((field) => field.source_type === 'custom')
  const req = (key: string, fallback = false) => isRequired(map, key, fallback)
  const title = vehicle.unit_number || vehicle.fleet_number || [vehicle.year, vehicle.make, vehicle.model].filter(Boolean).join(' ') || 'Vehicle'
  const agencyArchived = vehicle.agencies?.active === false

  return <>
    <PageHeader eyebrow="Fleet" title={title} description={`${vehicle.agencies?.name ?? 'Agency'} · ${vehicle.vehicle_types?.name ?? 'Vehicle record'}`} />
    {qs.saved && <div className="banner success"><div><strong>{qs.saved === 'archived' ? 'Vehicle archived' : qs.saved === 'restored' ? 'Vehicle restored' : 'Saved'}</strong><span>{qs.saved === 'archived' ? 'This vehicle is now excluded from active fleet workflows and reports. Historical records remain available.' : qs.saved === 'restored' ? 'This vehicle is active again and available for fleet and inspection workflows.' : 'Vehicle information was updated.'}</span></div></div>}
    {!vehicle.active && <div className="banner info"><div><strong>Archived vehicle</strong><span>This record is retained for history, but it is excluded from the current fleet, new inspections, compliance dashboards, and standard operational reports.</span></div></div>}
    {agencyArchived && <div className="banner info"><div><strong>Parent agency archived</strong><span>This vehicle remains stored as-is but is excluded from production workflows until {vehicle.agencies?.name || 'the agency'} is restored.</span></div></div>}
    {qs.error && <div className="banner danger"><div><strong>Unable to save</strong><span>{qs.error}</span></div></div>}

    <div className="dashboard-columns detail-columns">
      <form action={updateVehicle} className="form-card">
        <input type="hidden" name="id" value={vehicle.id} />
        <div className="form-card-heading"><div><span>Vehicle</span><h2>Master record</h2></div><span className={`pill ${vehicle.active && !agencyArchived ? 'green' : 'gray'}`}>{agencyArchived ? 'Agency archived' : vehicle.active ? 'Active' : 'Archived'}</span></div>
        <div className="form-grid three">
          {isEnabled(map,'agency_id') && <label className="field"><span>Agency{req('agency_id',true) ? ' *' : ''}</span><select name="agency_id" required={req('agency_id',true)} defaultValue={vehicle.agency_id}><option value="">Select agency</option>{agencies?.map((a) => <option key={a.id} value={a.id} disabled={!a.active && a.id !== vehicle.agency_id}>{a.name}{a.active ? '' : ' (Archived)'}</option>)}</select></label>}
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
        {narcoticsEnabled && <>
          <div className="form-section-divider"><span>Narcotics Management</span></div>
          <div className="form-grid">
            <label className="checkbox-field"><input type="checkbox" name="narcotics_count_required" defaultChecked={vehicle.narcotics_count_required}/><span>Require a signed daily narcotics count for this apparatus</span></label>
            <div className="field"><span>Daily count form</span><div className="readonly-field">{(() => { const currentType:any = (types ?? []).find((t:any) => t.id === vehicle.vehicle_type_id); const form:any = (narcoticsTemplates ?? []).find((t:any) => t.id === currentType?.narcotics_template_id); return form?.name || 'No form assigned to this vehicle type' })()}</div><small>Assigned automatically from the vehicle type in Narcotics → Forms & settings.</small></div>
          </div>
        </>}
        <CustomFieldInputs fields={custom} values={valueResult.values} />
        <div className="form-actions"><button className="primary-button" type="submit">Save changes</button></div>
      </form>

      <section className="panel">
        <div className="panel-heading"><h3>Record status</h3><span>Archive without deleting history</span></div>
        <p className="panel-copy">Archiving keeps licensing, inspection and audit history intact while removing the vehicle from normal production workflows, compliance calculations and standard reports.</p>
        {vehicle.active && !agencyArchived && <p><Link className="primary-button small button-link" href={`/inspections/new?vehicle=${vehicle.id}`}>Start inspection</Link></p>}
        <form action={setVehicleActive}>
          <input type="hidden" name="id" value={vehicle.id} />
          <input type="hidden" name="active" value={vehicle.active ? 'false' : 'true'} />
          <button className={vehicle.active ? 'secondary-button danger-outline' : 'primary-button'} type="submit">{vehicle.active ? 'Archive vehicle' : 'Restore vehicle'}</button>
        </form>
      </section>
    </div>

    <section className="report-section">
      <div className="section-heading"><div><span>Inspection history</span><h2>Completed inspection forms</h2><p>Submitted inspections for this apparatus remain attached to the vehicle record, including the exact form version used at the time of inspection.</p></div>{vehicle.active && !agencyArchived && <Link className="primary-button small button-link" href={`/inspections/new?vehicle=${vehicle.id}`}>Start inspection</Link>}</div>
      {inspectionHistoryError ? <div className="empty-state danger-text"><strong>Unable to load completed inspections</strong><span>{inspectionHistoryError.message}</span></div> : (completedInspections ?? []).length === 0 ? <div className="empty-state compact"><strong>No completed inspection forms yet</strong><span>Submitted inspections for this vehicle will appear here automatically.</span></div> : <div className="table-card"><table>
        <thead><tr><th>Date</th><th>Inspection form</th><th>Result</th><th>Inspector</th><th>Next due</th><th></th></tr></thead>
        <tbody>{(completedInspections ?? []).map((inspection:any) => {
          const formVersion = Array.isArray(inspection.inspection_form_versions) ? inspection.inspection_form_versions[0] : inspection.inspection_form_versions
          const template = Array.isArray(formVersion?.inspection_form_templates) ? formVersion?.inspection_form_templates[0] : formVersion?.inspection_form_templates
          const inspectionType = Array.isArray(inspection.inspection_types) ? inspection.inspection_types[0] : inspection.inspection_types
          const formLabel = template?.name || inspectionType?.name || 'Legacy inspection'
          const resultLabel = titleCase(inspection.result || 'submitted')
          const resultClass = inspection.result === 'passed' ? 'green' : inspection.result === 'passed_with_deficiencies' ? 'amber' : 'red'
          return <tr key={inspection.id}>
            <td><strong>{formatDate(inspection.inspection_date)}</strong>{inspection.submitted_at && <div className="muted-code">Submitted {new Date(inspection.submitted_at).toLocaleString()}</div>}</td>
            <td><strong>{formLabel}</strong>{formVersion?.version_number && <div className="muted-code">Form version {formVersion.version_number}</div>}</td>
            <td><span className={`pill ${resultClass}`}>{resultLabel}</span></td>
            <td>{inspection.inspector_name || '—'}</td>
            <td>{formatDate(inspection.next_due_date)}</td>
            <td className="table-action"><div className="inline-actions"><Link href={`/inspections/${inspection.id}`}>Open</Link><a className="text-link" href={`/inspections/${inspection.id}/pdf`}>PDF</a></div></td>
          </tr>
        })}</tbody>
      </table></div>}
    </section>
  </>
}
