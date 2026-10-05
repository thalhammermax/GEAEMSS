'use server'

import { revalidatePath } from 'next/cache'
import { redirect } from 'next/navigation'
import { requireSystemAdmin } from '@/lib/admin-auth'
import { DEFAULT_INSPECTION_PDF_SETTINGS } from '@/lib/inspection-pdf-settings'

function value(formData: FormData, key: string) {
  const raw = formData.get(key)
  return typeof raw === 'string' ? raw.trim() : ''
}

function checked(formData: FormData, key: string) {
  return formData.get(key) === 'on'
}

function fail(message: string): never {
  redirect(`/inspections/pdf-template?error=${encodeURIComponent(message)}`)
}

function required(formData: FormData, key: string, label: string) {
  const result = value(formData, key)
  if (!result) fail(`${label} is required.`)
  return result
}

function color(formData: FormData, key: string, label: string) {
  const result = required(formData, key, label).toUpperCase()
  if (!/^#[0-9A-F]{6}$/.test(result)) fail(`${label} must be a six-digit hex color such as #14314A.`)
  return result
}

export async function saveInspectionPdfTemplate(formData: FormData) {
  try {
    const { supabase, user } = await requireSystemAdmin()
    const payload = {
      id: 'system',
      organization_name: required(formData, 'organization_name', 'Organization name'),
      report_title: required(formData, 'report_title', 'Report title'),
      accent_color: color(formData, 'accent_color', 'Accent color'),
      heading_fill_color: color(formData, 'heading_fill_color', 'Section heading background'),
      summary_heading: required(formData, 'summary_heading', 'Summary heading'),
      notes_heading: required(formData, 'notes_heading', 'Notes heading'),
      checklist_heading: required(formData, 'checklist_heading', 'Checklist heading'),
      deficiencies_heading: required(formData, 'deficiencies_heading', 'Deficiencies heading'),
      footer_text: required(formData, 'footer_text', 'Footer text'),
      show_summary: checked(formData, 'show_summary'),
      show_vehicle_details: checked(formData, 'show_vehicle_details'),
      show_result_badge: checked(formData, 'show_result_badge'),
      show_form_version: checked(formData, 'show_form_version'),
      show_submitted_at: checked(formData, 'show_submitted_at'),
      show_inspection_id: checked(formData, 'show_inspection_id'),
      show_overall_notes: checked(formData, 'show_overall_notes'),
      show_checklist: checked(formData, 'show_checklist'),
      show_requirements: checked(formData, 'show_requirements'),
      show_observed_values: checked(formData, 'show_observed_values'),
      show_item_notes: checked(formData, 'show_item_notes'),
      show_deficiencies: checked(formData, 'show_deficiencies'),
      show_correction_notes: checked(formData, 'show_correction_notes'),
      show_generation_timestamp: checked(formData, 'show_generation_timestamp'),
      show_page_numbers: checked(formData, 'show_page_numbers'),
      show_draft_watermark: checked(formData, 'show_draft_watermark'),
      updated_by: user.id,
      updated_at: new Date().toISOString(),
    }

    const { error } = await supabase
      .from('inspection_pdf_template_settings')
      .upsert(payload, { onConflict: 'id' })

    if (error) throw error
  } catch (error: any) {
    fail(error?.message ?? 'The inspection PDF template could not be saved.')
  }

  revalidatePath('/inspections/pdf-template')
  redirect(`/inspections/pdf-template?notice=${encodeURIComponent('PDF template settings saved. New exports will use the updated template immediately.')}`)
}

export async function resetInspectionPdfTemplate() {
  try {
    const { supabase, user } = await requireSystemAdmin()
    const d = DEFAULT_INSPECTION_PDF_SETTINGS
    const { error } = await supabase
      .from('inspection_pdf_template_settings')
      .upsert({
        id: 'system',
        organization_name: d.organizationName,
        report_title: d.reportTitle,
        accent_color: d.accentColor,
        heading_fill_color: d.headingFillColor,
        summary_heading: d.summaryHeading,
        notes_heading: d.notesHeading,
        checklist_heading: d.checklistHeading,
        deficiencies_heading: d.deficienciesHeading,
        footer_text: d.footerText,
        show_summary: d.showSummary,
        show_vehicle_details: d.showVehicleDetails,
        show_result_badge: d.showResultBadge,
        show_form_version: d.showFormVersion,
        show_submitted_at: d.showSubmittedAt,
        show_inspection_id: d.showInspectionId,
        show_overall_notes: d.showOverallNotes,
        show_checklist: d.showChecklist,
        show_requirements: d.showRequirements,
        show_observed_values: d.showObservedValues,
        show_item_notes: d.showItemNotes,
        show_deficiencies: d.showDeficiencies,
        show_correction_notes: d.showCorrectionNotes,
        show_generation_timestamp: d.showGenerationTimestamp,
        show_page_numbers: d.showPageNumbers,
        show_draft_watermark: d.showDraftWatermark,
        updated_by: user.id,
        updated_at: new Date().toISOString(),
      }, { onConflict: 'id' })

    if (error) throw error
  } catch (error: any) {
    fail(error?.message ?? 'The inspection PDF template could not be reset.')
  }

  revalidatePath('/inspections/pdf-template')
  redirect(`/inspections/pdf-template?notice=${encodeURIComponent('PDF template restored to the GEAEMS defaults.')}`)
}
