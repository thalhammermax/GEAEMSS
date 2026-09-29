import Link from 'next/link'
import { saveInspection } from '@/app/(portal)/inspections/actions'
import { InspectionSection } from '@/components/inspection-section'

type Section = { id: string; title: string; sort_order: number; inspection_form_items: any[] }

type Props = {
  inspectionId?: string | null
  vehicle: any
  template: any
  formVersion: any
  sections: Section[]
  responses?: any[]
  defaults?: any
  readOnly?: boolean
}

export function DigitalInspectionForm({ inspectionId, vehicle, template, formVersion, sections, responses = [], defaults = {}, readOnly = false }: Props) {
  const responseMap = Object.fromEntries(responses.map((r: any) => [r.form_item_id, r]))
  const itemCount = sections.reduce((n, s) => n + (s.inspection_form_items?.length ?? 0), 0)
  const answeredCount = responses.filter((r: any) => r.status || r.observed_value).length
  const failedCount = responses.filter((r: any) => r.status === 'fail').length

  return <>
    <div className="inspection-summary-strip">
      <div><span>Vehicle</span><strong>{vehicle.unit_number || vehicle.fleet_number || 'Unnumbered'}</strong><small>{vehicle.agencies?.short_name || vehicle.agencies?.name || ''}</small></div>
      <div><span>Inspection form</span><strong>{template.name}</strong><small>Version {formVersion.version_number}</small></div>
      <div><span>Checklist</span><strong>{answeredCount} / {itemCount}</strong><small>items answered</small></div>
      <div><span>Deficiencies</span><strong>{failedCount}</strong><small>items marked deficient</small></div>
    </div>

    <form action={readOnly ? undefined : saveInspection}>
      <input type="hidden" name="inspection_id" value={inspectionId ?? ''} />
      <input type="hidden" name="vehicle_id" value={vehicle.id} />
      <input type="hidden" name="form_version_id" value={formVersion.id} />

      <section className="form-card inspection-header-card">
        <div className="form-card-heading"><div><span>Inspection record</span><h2>Inspection details</h2></div>{readOnly && <span className="pill green">Submitted</span>}</div>
        <div className="form-grid three">
          <label className="field"><span>Inspection date *</span><input name="inspection_date" type="date" required defaultValue={defaults.inspection_date ?? new Date().toISOString().slice(0,10)} disabled={readOnly} /></label>
          <label className="field"><span>Inspector *</span><input name="inspector_name" required defaultValue={defaults.inspector_name ?? ''} disabled={readOnly} /></label>
          <label className="field"><span>Inspector organization</span><input name="inspector_organization" defaultValue={defaults.inspector_organization ?? vehicle.agencies?.name ?? ''} disabled={readOnly} /></label>
          <label className="field"><span>Inspection location</span><input name="inspection_location" defaultValue={defaults.inspection_location ?? ''} disabled={readOnly} /></label>
          <label className="field"><span>Odometer</span><input name="odometer" type="number" min="0" step="1" defaultValue={defaults.odometer ?? ''} disabled={readOnly} /></label>
          <label className="field"><span>Final disposition</span><select name="final_result" defaultValue={defaults.result && defaults.result !== 'passed' ? defaults.result : 'passed_with_deficiencies'} disabled={readOnly}><option value="passed_with_deficiencies">Pass with deficiencies</option><option value="failed">Fail inspection</option><option value="out_of_service">Out of service</option></select><small>If there are no deficient items, submission is automatically recorded as Passed.</small></label>
          <label className="field span-full"><span>Overall notes</span><textarea name="inspection_notes" rows={3} defaultValue={defaults.notes ?? ''} disabled={readOnly} /></label>
        </div>
      </section>

      {sections.map((section) => <InspectionSection key={section.id} title={section.title} items={(section.inspection_form_items ?? []).sort((a:any,b:any)=>a.sort_order-b.sort_order)} responses={responseMap} readOnly={readOnly} />)}

      {!readOnly && <div className="inspection-submit-bar">
        <div><strong>Inspection not complete yet?</strong><span>Save a draft and return later. Submitting locks the inspection and creates deficiencies for failed items.</span></div>
        <div className="inline-actions"><Link className="secondary-button button-link" href="/inspections">Cancel</Link><button className="secondary-button" type="submit" name="mode" value="draft" formNoValidate>Save draft</button><button className="primary-button" type="submit" name="mode" value="submit">Submit inspection</button></div>
      </div>}
    </form>
  </>
}
