import type { Metadata } from 'next'
import Link from 'next/link'
import { redirect } from 'next/navigation'
import { PageHeader } from '@/components/page-header'
import { createClient } from '@/lib/supabase/server'
import { normalizeInspectionPdfSettings } from '@/lib/inspection-pdf-settings'
import { resetInspectionPdfTemplate, saveInspectionPdfTemplate } from './actions'

export const metadata: Metadata = { title: 'Inspection PDF Template' }
type Props = { searchParams: Promise<{ notice?: string; error?: string }> }

export default async function InspectionPdfTemplatePage({ searchParams }: Props) {
  const qs = await searchParams
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const [{ data: role }, { data: row, error }] = await Promise.all([
    supabase.from('user_roles').select('role').eq('user_id', user.id).eq('role', 'system_admin').maybeSingle(),
    supabase.from('inspection_pdf_template_settings').select('*').eq('id', 'system').maybeSingle(),
  ])
  if (!role) redirect('/inspections')

  const settings = normalizeInspectionPdfSettings(row)

  return <>
    <PageHeader
      eyebrow="Inspections"
      title="Inspection PDF template"
      description="Control the system-wide layout and content used when inspection records are exported to PDF."
      action={<div className="inline-actions"><a className="primary-button small button-link" href="/inspections/pdf-template/preview" target="_blank" rel="noreferrer">Preview sample PDF</a><Link className="secondary-button small button-link" href="/inspections">Back to inspections</Link></div>}
    />

    {qs.notice && <div className="banner success"><div><strong>Template updated</strong><span>{qs.notice}</span></div></div>}
    {qs.error && <div className="banner danger"><div><strong>Unable to save template</strong><span>{qs.error}</span></div></div>}
    {error && <div className="banner warning"><div><strong>PDF template settings are not available yet</strong><span>{error.message}. Run migration 018_inspection_pdf_template.sql, then reload this page.</span></div></div>}

    <div className="banner info"><div><strong>Changes apply to future PDF exports immediately.</strong><span>The underlying inspection record and historical form version are not changed. Re-exporting an old inspection uses the current PDF presentation template.</span></div></div>

    <div className="dashboard-columns detail-columns">
      <form action={saveInspectionPdfTemplate} className="form-card">
        <div className="form-card-heading"><div><span>Branding & layout</span><h2>PDF appearance</h2></div></div>

        <div className="form-grid two">
          <label className="field span-two"><span>Organization name</span><input name="organization_name" required defaultValue={settings.organizationName}/></label>
          <label className="field span-two"><span>Report title</span><input name="report_title" required defaultValue={settings.reportTitle}/></label>
          <label className="field"><span>Accent color</span><div className="inline-form"><input name="accent_color" required pattern="#[0-9A-Fa-f]{6}" defaultValue={settings.accentColor}/><input aria-label="Accent color picker" name="accent_color_picker" type="color" defaultValue={settings.accentColor.toLowerCase()} disabled/></div><small>Six-digit hex value, for example #14314A.</small></label>
          <label className="field"><span>Section heading background</span><input name="heading_fill_color" required pattern="#[0-9A-Fa-f]{6}" defaultValue={settings.headingFillColor}/><small>Six-digit hex value.</small></label>
        </div>

        <div className="form-section-divider"><span>Section headings</span></div>
        <div className="form-grid two">
          <label className="field"><span>Summary heading</span><input name="summary_heading" required defaultValue={settings.summaryHeading}/></label>
          <label className="field"><span>Overall notes heading</span><input name="notes_heading" required defaultValue={settings.notesHeading}/></label>
          <label className="field"><span>Checklist heading</span><input name="checklist_heading" required defaultValue={settings.checklistHeading}/></label>
          <label className="field"><span>Deficiencies heading</span><input name="deficiencies_heading" required defaultValue={settings.deficienciesHeading}/></label>
          <label className="field span-two"><span>Footer text</span><input name="footer_text" required defaultValue={settings.footerText}/></label>
        </div>

        <div className="form-section-divider"><span>PDF content</span></div>
        <div className="role-option-list">
          <label><input type="checkbox" name="show_summary" defaultChecked={settings.showSummary}/><span><strong>Inspection summary</strong><small>Date, inspection type, inspector, location, odometer and selected metadata.</small></span></label>
          <label><input type="checkbox" name="show_vehicle_details" defaultChecked={settings.showVehicleDetails}/><span><strong>Vehicle detail line</strong><small>Agency, year/make/model and vehicle type beneath the apparatus heading.</small></span></label>
          <label><input type="checkbox" name="show_result_badge" defaultChecked={settings.showResultBadge}/><span><strong>Result badge</strong><small>Passed, Passed With Deficiencies, Failed, Out of Service, or Draft.</small></span></label>
          <label><input type="checkbox" name="show_form_version" defaultChecked={settings.showFormVersion}/><span><strong>Inspection form version</strong><small>Shows the exact historical checklist version used for the inspection.</small></span></label>
          <label><input type="checkbox" name="show_submitted_at" defaultChecked={settings.showSubmittedAt}/><span><strong>Submission date/time</strong><small>Include the record submission timestamp in the summary.</small></span></label>
          <label><input type="checkbox" name="show_next_due" defaultChecked={settings.showNextDue}/><span><strong>Next due date</strong><small>Include the calculated next inspection due date.</small></span></label>
          <label><input type="checkbox" name="show_inspection_id" defaultChecked={settings.showInspectionId}/><span><strong>Inspection ID</strong><small>Include the UUID in the summary/footer for audit traceability.</small></span></label>
          <label><input type="checkbox" name="show_overall_notes" defaultChecked={settings.showOverallNotes}/><span><strong>Overall inspection notes</strong><small>Include the inspection-level notes section when notes exist.</small></span></label>
          <label><input type="checkbox" name="show_checklist" defaultChecked={settings.showChecklist}/><span><strong>Full inspection checklist</strong><small>Include all checklist sections and responses.</small></span></label>
          <label><input type="checkbox" name="show_requirements" defaultChecked={settings.showRequirements}/><span><strong>Requirement text</strong><small>Show the required quantity/standard beneath each checklist item.</small></span></label>
          <label><input type="checkbox" name="show_observed_values" defaultChecked={settings.showObservedValues}/><span><strong>Observed values / counts</strong><small>Show entered quantities and informational answers.</small></span></label>
          <label><input type="checkbox" name="show_item_notes" defaultChecked={settings.showItemNotes}/><span><strong>Checklist item notes</strong><small>Include notes recorded against individual inspection items.</small></span></label>
          <label><input type="checkbox" name="show_deficiencies" defaultChecked={settings.showDeficiencies}/><span><strong>Deficiencies & corrective actions</strong><small>Include the deficiency summary after the checklist.</small></span></label>
          <label><input type="checkbox" name="show_correction_notes" defaultChecked={settings.showCorrectionNotes}/><span><strong>Corrective-action notes</strong><small>Include correction notes beneath deficiency records.</small></span></label>
          <label><input type="checkbox" name="show_generation_timestamp" defaultChecked={settings.showGenerationTimestamp}/><span><strong>PDF generation timestamp</strong><small>Show when the PDF was generated in the footer.</small></span></label>
          <label><input type="checkbox" name="show_page_numbers" defaultChecked={settings.showPageNumbers}/><span><strong>Page numbers</strong><small>Show Page X of Y in the footer.</small></span></label>
          <label><input type="checkbox" name="show_draft_watermark" defaultChecked={settings.showDraftWatermark}/><span><strong>Draft watermark</strong><small>Watermark PDFs exported from an inspection that has not been submitted.</small></span></label>
        </div>

        <div className="form-actions"><button className="primary-button" type="submit" disabled={!!error}>Save PDF template</button><a className="secondary-button button-link" href="/inspections/pdf-template/preview" target="_blank" rel="noreferrer">Preview sample PDF</a></div>
      </form>

      <div>
        <section className="panel">
          <div className="panel-heading"><h3>Template preview</h3><span>Approximate on-screen preview</span></div>
          <div style={{background:'#fff', border:'1px solid #d9dee3', borderRadius:'4px', padding:'22px', boxShadow:'0 2px 8px rgba(0,0,0,.05)'}}>
            <div style={{fontSize:'11px', fontWeight:700, color:settings.accentColor}}>{settings.organizationName}</div>
            <div style={{fontSize:'9px', marginTop:'3px', color:'#69737d'}}>{settings.reportTitle}</div>
            <div style={{borderTop:'1px solid #ccd3da', margin:'10px 0 18px'}}/>
            <div style={{display:'flex', justifyContent:'space-between', gap:'12px', alignItems:'center'}}>
              <div><strong style={{fontSize:'20px', color:settings.accentColor}}>M61</strong>{settings.showVehicleDetails && <div style={{fontSize:'10px', color:'#69737d', marginTop:'4px'}}>Example Fire District · 2026 Ambulance · ALS Ambulance</div>}</div>
              {settings.showResultBadge && <span style={{padding:'5px 9px', fontSize:'9px', fontWeight:700, background:'#1f7a47', color:'#fff'}}>PASSED</span>}
            </div>
            {settings.showSummary && <><div style={{background:settings.headingFillColor, color:settings.accentColor, fontWeight:700, marginTop:'18px', padding:'7px 9px'}}>{settings.summaryHeading}</div><div style={{fontSize:'10px', lineHeight:1.7, marginTop:'8px'}}>Inspection date: Oct 1, 2026<br/>Inspector: Sample Inspector<br/>Location: GEAEMS System Office</div></>}
            {settings.showChecklist && <><div style={{background:settings.headingFillColor, color:settings.accentColor, fontWeight:700, marginTop:'18px', padding:'7px 9px'}}>{settings.checklistHeading}</div><div style={{fontSize:'10px', marginTop:'8px'}}><strong>1. Portable Oxygen Cylinder</strong>{settings.showRequirements && <div style={{color:'#69737d'}}>Required: 1 with regulator</div>}<div style={{color:'#1f7a47', fontWeight:700, marginTop:'3px'}}>COMPLIANT</div></div></>}
            <div style={{borderTop:'1px solid #d9dee3', marginTop:'20px', paddingTop:'7px', fontSize:'8px', color:'#79828b'}}>{settings.footerText}{settings.showGenerationTimestamp ? ' · Generated Oct 1, 2026' : ''}</div>
          </div>
          <p className="panel-copy">Use <strong>Preview sample PDF</strong> for the actual server-generated PDF. This card is only a quick approximation of the saved settings.</p>
        </section>

        <section className="panel">
          <div className="panel-heading"><h3>Reset template</h3><span>Return to GEAEMS defaults</span></div>
          <p className="panel-copy">This resets the PDF presentation only. Inspection records, completed forms, responses, and deficiencies are not changed.</p>
          <form action={resetInspectionPdfTemplate}><button className="secondary-button danger-outline" type="submit" disabled={!!error}>Restore default PDF template</button></form>
        </section>
      </div>
    </div>
  </>
}
