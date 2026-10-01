export type InspectionPdfSettings = {
  organizationName: string
  reportTitle: string
  accentColor: string
  headingFillColor: string
  summaryHeading: string
  notesHeading: string
  checklistHeading: string
  deficienciesHeading: string
  footerText: string
  showSummary: boolean
  showVehicleDetails: boolean
  showResultBadge: boolean
  showFormVersion: boolean
  showSubmittedAt: boolean
  showNextDue: boolean
  showInspectionId: boolean
  showOverallNotes: boolean
  showChecklist: boolean
  showRequirements: boolean
  showObservedValues: boolean
  showItemNotes: boolean
  showDeficiencies: boolean
  showCorrectionNotes: boolean
  showGenerationTimestamp: boolean
  showPageNumbers: boolean
  showDraftWatermark: boolean
}

export const DEFAULT_INSPECTION_PDF_SETTINGS: InspectionPdfSettings = {
  organizationName: 'GREATER ELGIN AREA EMS SYSTEM',
  reportTitle: 'VEHICLE INSPECTION REPORT',
  accentColor: '#14314A',
  headingFillColor: '#EDF2F7',
  summaryHeading: 'Inspection Summary',
  notesHeading: 'Overall Notes',
  checklistHeading: 'Inspection Checklist',
  deficienciesHeading: 'Deficiencies & Corrective Actions',
  footerText: 'Generated from GEAEMS Portal',
  showSummary: true,
  showVehicleDetails: true,
  showResultBadge: true,
  showFormVersion: true,
  showSubmittedAt: true,
  showNextDue: true,
  showInspectionId: true,
  showOverallNotes: true,
  showChecklist: true,
  showRequirements: true,
  showObservedValues: true,
  showItemNotes: true,
  showDeficiencies: true,
  showCorrectionNotes: true,
  showGenerationTimestamp: true,
  showPageNumbers: true,
  showDraftWatermark: true,
}

function bool(value: unknown, fallback: boolean) {
  return typeof value === 'boolean' ? value : fallback
}

function text(value: unknown, fallback: string) {
  return typeof value === 'string' && value.trim() ? value.trim() : fallback
}

function color(value: unknown, fallback: string) {
  const candidate = typeof value === 'string' ? value.trim() : ''
  return /^#[0-9A-Fa-f]{6}$/.test(candidate) ? candidate.toUpperCase() : fallback
}

export function normalizeInspectionPdfSettings(row?: any | null): InspectionPdfSettings {
  const d = DEFAULT_INSPECTION_PDF_SETTINGS
  if (!row) return { ...d }

  return {
    organizationName: text(row.organization_name ?? row.organizationName, d.organizationName),
    reportTitle: text(row.report_title ?? row.reportTitle, d.reportTitle),
    accentColor: color(row.accent_color ?? row.accentColor, d.accentColor),
    headingFillColor: color(row.heading_fill_color ?? row.headingFillColor, d.headingFillColor),
    summaryHeading: text(row.summary_heading ?? row.summaryHeading, d.summaryHeading),
    notesHeading: text(row.notes_heading ?? row.notesHeading, d.notesHeading),
    checklistHeading: text(row.checklist_heading ?? row.checklistHeading, d.checklistHeading),
    deficienciesHeading: text(row.deficiencies_heading ?? row.deficienciesHeading, d.deficienciesHeading),
    footerText: text(row.footer_text ?? row.footerText, d.footerText),
    showSummary: bool(row.show_summary ?? row.showSummary, d.showSummary),
    showVehicleDetails: bool(row.show_vehicle_details ?? row.showVehicleDetails, d.showVehicleDetails),
    showResultBadge: bool(row.show_result_badge ?? row.showResultBadge, d.showResultBadge),
    showFormVersion: bool(row.show_form_version ?? row.showFormVersion, d.showFormVersion),
    showSubmittedAt: bool(row.show_submitted_at ?? row.showSubmittedAt, d.showSubmittedAt),
    showNextDue: bool(row.show_next_due ?? row.showNextDue, d.showNextDue),
    showInspectionId: bool(row.show_inspection_id ?? row.showInspectionId, d.showInspectionId),
    showOverallNotes: bool(row.show_overall_notes ?? row.showOverallNotes, d.showOverallNotes),
    showChecklist: bool(row.show_checklist ?? row.showChecklist, d.showChecklist),
    showRequirements: bool(row.show_requirements ?? row.showRequirements, d.showRequirements),
    showObservedValues: bool(row.show_observed_values ?? row.showObservedValues, d.showObservedValues),
    showItemNotes: bool(row.show_item_notes ?? row.showItemNotes, d.showItemNotes),
    showDeficiencies: bool(row.show_deficiencies ?? row.showDeficiencies, d.showDeficiencies),
    showCorrectionNotes: bool(row.show_correction_notes ?? row.showCorrectionNotes, d.showCorrectionNotes),
    showGenerationTimestamp: bool(row.show_generation_timestamp ?? row.showGenerationTimestamp, d.showGenerationTimestamp),
    showPageNumbers: bool(row.show_page_numbers ?? row.showPageNumbers, d.showPageNumbers),
    showDraftWatermark: bool(row.show_draft_watermark ?? row.showDraftWatermark, d.showDraftWatermark),
  }
}
