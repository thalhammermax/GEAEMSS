import type { ModuleKey } from './modules'

export type ReportFieldType = 'text' | 'number' | 'date' | 'boolean'

export type ReportField = {
  key: string
  label: string
  type: ReportFieldType
  default?: boolean
  module?: ModuleKey
}

export type ReportSource = {
  key: string
  label: string
  description: string
  fields: ReportField[]
}

export type ReportFilter = {
  field: string
  operator: string
  value?: string
}

export type ReportSchedule = {
  enabled?: boolean
  frequency?: 'daily' | 'weekly' | 'monthly'
  timezone?: string
  hour?: number
  weekday?: number | null
  dayOfMonth?: number | null
  recipients?: string[]
  deliveryMode?: 'inline' | 'csv' | 'inline_csv'
}

export type ReportDefinition = {
  id?: string
  name?: string
  description?: string
  dataSource: string
  columns: string[]
  filters: ReportFilter[]
  sortField?: string
  sortDirection?: 'asc' | 'desc'
  groupField?: string
  schedule?: ReportSchedule
}

export type BuiltInReport = {
  key: string
  name: string
  description: string
  definition: ReportDefinition
}

export const REPORT_SOURCE_MODULES: Record<string, ModuleKey[]> = {
  personnel: ['personnel'],
  agencies: [],
  credential_compliance: ['personnel','credentials'],
  credential_records: ['personnel','credentials'],
  credential_history: ['personnel','credentials'],
  credential_submissions: ['personnel','credentials'],
  credential_type_census: ['credentials'],
  fleet: ['fleet'],
  vehicle_operations: ['fleet','inspections'],
  provider_operations: ['personnel'],
  vehicle_license_compliance: ['fleet'],
  inspection_compliance: ['fleet','inspections'],
  inspection_history: ['fleet','inspections'],
  inspection_deficiencies: ['fleet','inspections'],
  ce_completions: ['personnel','ce'],
  ce_attendance_history: ['personnel','ce'],
  narcotics_history: ['fleet','narcotics'],
  agency_compliance_summary: ['personnel','credentials','fleet','inspections'],
}

export function sourceRequiredModules(key: string) {
  return REPORT_SOURCE_MODULES[key] ?? []
}

export function sourceAvailableForModules(key: string, enabled: Set<ModuleKey> | ModuleKey[]) {
  const set = enabled instanceof Set ? enabled : new Set(enabled)
  return sourceRequiredModules(key).every((module) => set.has(module))
}

export const REPORT_SOURCES: ReportSource[] = [
  {
    key: 'personnel', label: 'Personnel', description: 'Provider demographic, level, status and agency-affiliation data.', fields: [
      { key: 'provider_name', label: 'Provider Name', type: 'text', default: true },
      { key: 'provider_number', label: 'System Provider ID', type: 'text', default: true },
      { key: 'first_name', label: 'First Name', type: 'text' },
      { key: 'middle_name', label: 'Middle Name', type: 'text' },
      { key: 'last_name', label: 'Last Name', type: 'text' },
      { key: 'preferred_name', label: 'Preferred Name', type: 'text' },
      { key: 'provider_level', label: 'Provider Level', type: 'text', default: true },
      { key: 'provider_status', label: 'Provider Status', type: 'text', default: true },
      { key: 'agencies', label: 'Active Agencies', type: 'text', default: true },
      { key: 'primary_agency', label: 'Primary Agency', type: 'text' },
      { key: 'email', label: 'Email', type: 'text', default: true },
      { key: 'phone', label: 'Phone', type: 'text' },
      { key: 'system_entry_date', label: 'System Entry Date', type: 'date' },
      { key: 'active_agency_count', label: 'Active Agency Count', type: 'number' },
    ]
  },
  {
    key: 'agencies', label: 'Agencies', description: 'Agency directory and status information.', fields: [
      { key: 'agency_name', label: 'Agency Name', type: 'text', default: true },
      { key: 'short_name', label: 'Short Name', type: 'text', default: true },
      { key: 'active', label: 'Active', type: 'boolean', default: true },
      { key: 'provider_count', label: 'Active Provider Count', type: 'number', default: true },
      { key: 'vehicle_count', label: 'Active Vehicle Count', type: 'number', default: true },
    ]
  },
  {
    key: 'credential_compliance', label: 'Credential Compliance', description: 'Required credentials and current compliance status.', fields: [
      { key: 'provider_name', label: 'Provider Name', type: 'text', default: true },
      { key: 'agencies', label: 'Agencies', type: 'text', default: true },
      { key: 'provider_level', label: 'Provider Level', type: 'text' },
      { key: 'credential_name', label: 'Credential', type: 'text', default: true },
      { key: 'credential_scope', label: 'Credential Scope', type: 'text' },
      { key: 'expiration_date', label: 'Expiration Date', type: 'date', default: true },
      { key: 'compliance_status', label: 'Status', type: 'text', default: true },
      { key: 'days_remaining', label: 'Days Remaining', type: 'number', default: true },
    ]
  },
  {
    key: 'credential_records', label: 'Current Credential Records', description: 'Verified current credential records, including credential numbers and dates.', fields: [
      { key: 'provider_name', label: 'Provider Name', type: 'text', default: true },
      { key: 'agencies', label: 'Agencies', type: 'text', default: true },
      { key: 'credential_name', label: 'Credential', type: 'text', default: true },
      { key: 'category', label: 'Category', type: 'text' },
      { key: 'credential_number', label: 'Credential Number', type: 'text' },
      { key: 'issue_date', label: 'Issue Date', type: 'date' },
      { key: 'expiration_date', label: 'Expiration Date', type: 'date', default: true },
      { key: 'status', label: 'Status', type: 'text', default: true },
      { key: 'days_remaining', label: 'Days Remaining', type: 'number' },
      { key: 'source', label: 'Source', type: 'text' },
    ]
  },
  {
    key: 'credential_history', label: 'Credential History', description: 'Historical provider credential records, including superseded credentials.', fields: [
      { key: 'provider_name', label: 'Provider Name', type: 'text', default: true },
      { key: 'agencies', label: 'Agencies', type: 'text', default: true },
      { key: 'credential_name', label: 'Credential', type: 'text', default: true },
      { key: 'credential_number', label: 'Credential Number', type: 'text' },
      { key: 'issue_date', label: 'Issue Date', type: 'date' },
      { key: 'expiration_date', label: 'Expiration Date', type: 'date', default: true },
      { key: 'verification_status', label: 'Verification Status', type: 'text' },
      { key: 'is_current', label: 'Current Record', type: 'boolean', default: true },
      { key: 'source', label: 'Source', type: 'text' },
      { key: 'created_at', label: 'Recorded At', type: 'date' },
    ]
  },
  {
    key: 'credential_submissions', label: 'Credential Submissions', description: 'Provider credential renewal submissions and review status.', fields: [
      { key: 'provider_name', label: 'Provider Name', type: 'text', default: true },
      { key: 'agencies', label: 'Agencies', type: 'text', default: true },
      { key: 'credential_name', label: 'Credential', type: 'text', default: true },
      { key: 'status', label: 'Submission Status', type: 'text', default: true },
      { key: 'credential_number', label: 'Credential Number', type: 'text' },
      { key: 'expiration_date', label: 'Expiration Date', type: 'date' },
      { key: 'submitted_at', label: 'Submitted At', type: 'date', default: true },
      { key: 'reviewed_at', label: 'Reviewed At', type: 'date' },
      { key: 'review_notes', label: 'Review Notes', type: 'text' },
    ]
  },
  {
    key: 'credential_type_census', label: 'Credential Type Census', description: 'Counts of current verified credentials by credential definition.', fields: [
      { key: 'credential_name', label: 'Credential', type: 'text', default: true },
      { key: 'category', label: 'Category', type: 'text', default: true },
      { key: 'scope', label: 'Scope', type: 'text' },
      { key: 'active_records', label: 'Current Verified Records', type: 'number', default: true },
      { key: 'expiring_90_days', label: 'Expiring Within 90 Days', type: 'number', default: true },
      { key: 'expired_records', label: 'Expired Records', type: 'number', default: true },
    ]
  },
  {
    key: 'vehicle_operations', label: 'Vehicle + Inspection Operations', description: 'One row per vehicle combining Fleet and Inspection data. Narcotics fields become available automatically when that module is enabled.', fields: [
      { key: 'agency', label: 'Agency', type: 'text', default: true, module: 'fleet' },
      { key: 'unit_number', label: 'Unit Number', type: 'text', default: true, module: 'fleet' },
      { key: 'fleet_number', label: 'Fleet Number', type: 'text', module: 'fleet' },
      { key: 'vehicle_type', label: 'Vehicle Type', type: 'text', default: true, module: 'fleet' },
      { key: 'vehicle_status', label: 'Vehicle Status', type: 'text', default: true, module: 'fleet' },
      { key: 'vin', label: 'VIN', type: 'text', module: 'fleet' },
      { key: 'year', label: 'Year', type: 'number', module: 'fleet' },
      { key: 'make', label: 'Make', type: 'text', module: 'fleet' },
      { key: 'model', label: 'Model', type: 'text', module: 'fleet' },
      { key: 'license_plate', label: 'License Plate', type: 'text', module: 'fleet' },
      { key: 'license_plate_state', label: 'Plate State', type: 'text', module: 'fleet' },
      { key: 'in_service_date', label: 'In Service Date', type: 'date', module: 'fleet' },

      { key: 'inspection_requirement_count', label: 'Required Inspection Types', type: 'number', module: 'inspections' },
      { key: 'inspection_issue_count', label: 'Inspection Compliance Issues', type: 'number', default: true, module: 'inspections' },
      { key: 'inspection_compliance_status', label: 'Worst Inspection Status', type: 'text', default: true, module: 'inspections' },
      { key: 'next_inspection_due', label: 'Next Inspection Due', type: 'date', default: true, module: 'inspections' },
      { key: 'latest_inspection_date', label: 'Latest Completed Inspection', type: 'date', default: true, module: 'inspections' },
      { key: 'latest_inspection_type', label: 'Latest Inspection Type', type: 'text', module: 'inspections' },
      { key: 'latest_inspection_result', label: 'Latest Inspection Result', type: 'text', default: true, module: 'inspections' },
      { key: 'latest_inspector', label: 'Latest Inspector', type: 'text', module: 'inspections' },
      { key: 'overdue_inspection_count', label: 'Overdue Inspections', type: 'number', module: 'inspections' },
      { key: 'failed_inspection_count', label: 'Failed / OOS Inspections', type: 'number', module: 'inspections' },
      { key: 'missing_inspection_count', label: 'Missing / Unscheduled Inspections', type: 'number', module: 'inspections' },
      { key: 'open_deficiency_count', label: 'Open Deficiencies', type: 'number', default: true, module: 'inspections' },
      { key: 'critical_deficiency_count', label: 'Critical Open Deficiencies', type: 'number', default: true, module: 'inspections' },

      { key: 'narcotics_count_required', label: 'Daily Narcotics Count Required', type: 'boolean', module: 'narcotics' },
      { key: 'latest_narcotics_count_date', label: 'Latest Narcotics Count', type: 'date', module: 'narcotics' },
      { key: 'latest_narcotics_seal', label: 'Latest Seal Number', type: 'text', module: 'narcotics' },
      { key: 'latest_narcotics_signed_by', label: 'Latest Narcotics Signer', type: 'text', module: 'narcotics' },
      { key: 'latest_narcotics_discrepancy', label: 'Latest Count Has Discrepancy', type: 'boolean', module: 'narcotics' },
    ]
  },
  {
    key: 'provider_operations', label: 'Provider + Credential + CE Overview', description: 'One row per provider. Personnel fields are always present; Credential and CE fields appear as those modules are enabled.', fields: [
      { key: 'provider_name', label: 'Provider Name', type: 'text', default: true, module: 'personnel' },
      { key: 'provider_number', label: 'System Provider ID', type: 'text', default: true, module: 'personnel' },
      { key: 'provider_level', label: 'Provider Level', type: 'text', default: true, module: 'personnel' },
      { key: 'provider_status', label: 'Provider Status', type: 'text', default: true, module: 'personnel' },
      { key: 'agencies', label: 'Active Agencies', type: 'text', default: true, module: 'personnel' },
      { key: 'primary_agency', label: 'Primary Agency', type: 'text', module: 'personnel' },
      { key: 'email', label: 'Email', type: 'text', module: 'personnel' },
      { key: 'phone', label: 'Phone', type: 'text', module: 'personnel' },
      { key: 'system_entry_date', label: 'System Entry Date', type: 'date', module: 'personnel' },

      { key: 'required_credential_count', label: 'Required Credential Count', type: 'number', module: 'credentials' },
      { key: 'credential_issue_count', label: 'Credential Compliance Issues', type: 'number', module: 'credentials' },
      { key: 'missing_credential_count', label: 'Missing Credentials', type: 'number', module: 'credentials' },
      { key: 'expired_credential_count', label: 'Expired Credentials', type: 'number', module: 'credentials' },
      { key: 'expiring_credential_count', label: 'Expiring Soon Credentials', type: 'number', module: 'credentials' },
      { key: 'pending_credential_submissions', label: 'Pending Credential Submissions', type: 'number', module: 'credentials' },
      { key: 'next_credential_expiration', label: 'Next Credential Expiration', type: 'date', module: 'credentials' },

      { key: 'ce_total_hours', label: 'Total Approved CE Hours', type: 'number', module: 'ce' },
      { key: 'ce_hours_12_months', label: 'CE Hours - Last 12 Months', type: 'number', module: 'ce' },
      { key: 'ce_completion_count', label: 'CE Completion Count', type: 'number', module: 'ce' },
      { key: 'latest_ce_date', label: 'Latest CE Completion', type: 'date', module: 'ce' },
      { key: 'pending_external_ce', label: 'Pending External CE', type: 'number', module: 'ce' },
    ]
  },
  {
    key: 'fleet', label: 'Fleet', description: 'Vehicle roster, agency, vehicle type and status.', fields: [
      { key: 'agency', label: 'Agency', type: 'text', default: true },
      { key: 'unit_number', label: 'Unit Number', type: 'text', default: true },
      { key: 'fleet_number', label: 'Fleet Number', type: 'text' },
      { key: 'vehicle_type', label: 'Vehicle Type', type: 'text', default: true },
      { key: 'vehicle_status', label: 'Status', type: 'text', default: true },
      { key: 'vin', label: 'VIN', type: 'text' },
      { key: 'year', label: 'Year', type: 'number' },
      { key: 'make', label: 'Make', type: 'text' },
      { key: 'model', label: 'Model', type: 'text' },
      { key: 'license_plate', label: 'License Plate', type: 'text' },
      { key: 'license_plate_state', label: 'Plate State', type: 'text' },
      { key: 'in_service_date', label: 'In Service Date', type: 'date' },
      { key: 'narcotics_count_required', label: 'Daily Narcotics Count Required', type: 'boolean' },
    ]
  },
  {
    key: 'vehicle_license_compliance', label: 'Vehicle License Compliance', description: 'Required vehicle licenses and expiration status.', fields: [
      { key: 'agency', label: 'Agency', type: 'text', default: true },
      { key: 'unit_number', label: 'Unit Number', type: 'text', default: true },
      { key: 'license_name', label: 'License', type: 'text', default: true },
      { key: 'expiration_date', label: 'Expiration Date', type: 'date', default: true },
      { key: 'compliance_status', label: 'Status', type: 'text', default: true },
      { key: 'days_remaining', label: 'Days Remaining', type: 'number' },
    ]
  },
  {
    key: 'inspection_compliance', label: 'Inspection Compliance', description: 'Vehicle inspection due dates and compliance status.', fields: [
      { key: 'agency', label: 'Agency', type: 'text', default: true },
      { key: 'unit_number', label: 'Unit Number', type: 'text', default: true },
      { key: 'inspection_name', label: 'Inspection Type', type: 'text', default: true },
      { key: 'latest_inspection_date', label: 'Latest Inspection', type: 'date' },
      { key: 'latest_result', label: 'Latest Result', type: 'text' },
      { key: 'next_due_date', label: 'Next Due', type: 'date', default: true },
      { key: 'compliance_status', label: 'Status', type: 'text', default: true },
      { key: 'days_until_due', label: 'Days Until Due', type: 'number' },
    ]
  },
  {
    key: 'inspection_history', label: 'Inspection History', description: 'Completed and accessible vehicle inspection records.', fields: [
      { key: 'inspection_date', label: 'Inspection Date', type: 'date', default: true },
      { key: 'agency', label: 'Agency', type: 'text', default: true },
      { key: 'unit_number', label: 'Unit Number', type: 'text', default: true },
      { key: 'inspection_type', label: 'Inspection Type', type: 'text', default: true },
      { key: 'workflow_status', label: 'Workflow Status', type: 'text' },
      { key: 'result', label: 'Result', type: 'text', default: true },
      { key: 'inspector_name', label: 'Inspector', type: 'text', default: true },
      { key: 'inspection_location', label: 'Location', type: 'text' },
      { key: 'odometer', label: 'Odometer', type: 'number' },
      { key: 'submitted_at', label: 'Submitted At', type: 'date' },
    ]
  },
  {
    key: 'inspection_deficiencies', label: 'Inspection Deficiencies', description: 'Inspection deficiencies and corrective-action status.', fields: [
      { key: 'inspection_date', label: 'Inspection Date', type: 'date', default: true },
      { key: 'agency', label: 'Agency', type: 'text', default: true },
      { key: 'unit_number', label: 'Unit Number', type: 'text', default: true },
      { key: 'description', label: 'Deficiency', type: 'text', default: true },
      { key: 'severity', label: 'Severity', type: 'text', default: true },
      { key: 'status', label: 'Status', type: 'text', default: true },
      { key: 'correction_due_date', label: 'Correction Due', type: 'date' },
      { key: 'corrected_at', label: 'Corrected At', type: 'date' },
      { key: 'correction_notes', label: 'Correction Notes', type: 'text' },
    ]
  },
  {
    key: 'ce_completions', label: 'CE Completion History', description: 'Completed continuing education from verified GEAEMS sessions and approved external certificates.', fields: [
      { key: 'provider_name', label: 'Provider Name', type: 'text', default: true },
      { key: 'agencies', label: 'Agencies', type: 'text', default: true },
      { key: 'completion_date', label: 'Completion Date', type: 'date', default: true },
      { key: 'course_title', label: 'Course / Training', type: 'text', default: true },
      { key: 'course_code', label: 'Course Code', type: 'text' },
      { key: 'category', label: 'Category', type: 'text', default: true },
      { key: 'delivery_source', label: 'Source', type: 'text', default: true },
      { key: 'sponsor_or_location', label: 'Sponsor / Location', type: 'text' },
      { key: 'credit_hours', label: 'CE Hours', type: 'number', default: true },
      { key: 'verification_method', label: 'Verification Method', type: 'text' },
      { key: 'verified_at', label: 'Verified / Approved At', type: 'date' },
    ]
  },
  {
    key: 'ce_attendance_history', label: 'CE Session Attendance', description: 'Attendance status, check-in, verification, and awarded credit for scheduled GEAEMS CE sessions.', fields: [
      { key: 'provider_name', label: 'Provider Name', type: 'text', default: true },
      { key: 'agencies', label: 'Agencies', type: 'text', default: true },
      { key: 'session_date', label: 'Session Date', type: 'date', default: true },
      { key: 'course_title', label: 'CE Class', type: 'text', default: true },
      { key: 'course_code', label: 'Course Code', type: 'text' },
      { key: 'category', label: 'Category', type: 'text' },
      { key: 'location', label: 'Location', type: 'text', default: true },
      { key: 'attendance_status', label: 'Attendance Status', type: 'text', default: true },
      { key: 'checked_in_at', label: 'Checked In At', type: 'date' },
      { key: 'verified_at', label: 'Verified At', type: 'date' },
      { key: 'verification_method', label: 'Verification Method', type: 'text' },
      { key: 'entry_source', label: 'Entry Source', type: 'text' },
      { key: 'credit_hours', label: 'CE Hours', type: 'number', default: true },
    ]
  },
  {
    key: 'narcotics_history', label: 'Narcotics Count History', description: 'Submitted narcotics counts available to System and Agency Administration.', fields: [
      { key: 'count_date', label: 'Count Date', type: 'date', default: true },
      { key: 'agency', label: 'Agency', type: 'text', default: true },
      { key: 'unit_number', label: 'Apparatus', type: 'text', default: true },
      { key: 'form_name', label: 'Narcotics Form', type: 'text' },
      { key: 'seal_number', label: 'Seal Number', type: 'text', default: true },
      { key: 'prior_seal_number', label: 'Previous Seal', type: 'text' },
      { key: 'seal_change_reason', label: 'Seal Change Reason', type: 'text' },
      { key: 'signed_name', label: 'Signed By', type: 'text', default: true },
      { key: 'signed_at', label: 'Signed At', type: 'date', default: true },
      { key: 'has_discrepancy', label: 'Has Discrepancy', type: 'boolean', default: true },
    ]
  },
  {
    key: 'agency_compliance_summary', label: 'Agency Compliance Summary', description: 'High-level provider, credential, fleet and inspection compliance by agency.', fields: [
      { key: 'agency', label: 'Agency', type: 'text', default: true },
      { key: 'active_providers', label: 'Active Providers', type: 'number', default: true },
      { key: 'credential_issues', label: 'Credential Issues', type: 'number', default: true },
      { key: 'active_vehicles', label: 'Active Vehicles', type: 'number', default: true },
      { key: 'vehicle_license_issues', label: 'Vehicle License Issues', type: 'number', default: true },
      { key: 'inspection_issues', label: 'Inspection Issues', type: 'number', default: true },
      { key: 'open_deficiencies', label: 'Open Deficiencies', type: 'number', default: true },
    ]
  },
]

export const BUILTIN_REPORTS: BuiltInReport[] = [
  { key: 'system-personnel-roster', name: 'System Personnel Roster', description: 'Active provider roster with level, status, agency and contact information.', definition: { dataSource: 'personnel', columns: ['provider_name','provider_number','provider_level','provider_status','agencies','email','phone'], filters: [], sortField: 'provider_name', sortDirection: 'asc' } },
  { key: 'agency-personnel-roster', name: 'Agency Personnel Roster', description: 'Personnel roster scoped automatically to the agencies you administer.', definition: { dataSource: 'personnel', columns: ['provider_name','provider_number','provider_level','provider_status','agencies','email'], filters: [], sortField: 'provider_name', sortDirection: 'asc', groupField: 'primary_agency' } },
  { key: 'credential-compliance', name: 'Credential Compliance', description: 'All required provider credentials and their current compliance status.', definition: { dataSource: 'credential_compliance', columns: ['provider_name','agencies','provider_level','credential_name','expiration_date','compliance_status','days_remaining'], filters: [], sortField: 'provider_name', sortDirection: 'asc' } },
  { key: 'credential-expiration', name: 'Credential Expiration', description: 'Credential requirements ordered by expiration date.', definition: { dataSource: 'credential_compliance', columns: ['provider_name','agencies','credential_name','expiration_date','compliance_status','days_remaining'], filters: [{ field:'compliance_status', operator:'not_equals', value:'MISSING' }], sortField: 'expiration_date', sortDirection: 'asc' } },
  { key: 'missing-credentials', name: 'Missing Required Credentials', description: 'Providers missing a credential currently required by the System or an agency.', definition: { dataSource: 'credential_compliance', columns: ['provider_name','agencies','provider_level','credential_name','credential_scope','compliance_status'], filters: [{ field:'compliance_status', operator:'equals', value:'MISSING' }], sortField: 'provider_name', sortDirection: 'asc' } },
  { key: 'expired-credentials', name: 'Expired Credentials', description: 'Required provider credentials that are currently expired.', definition: { dataSource: 'credential_compliance', columns: ['provider_name','agencies','credential_name','expiration_date','days_remaining'], filters: [{ field:'compliance_status', operator:'equals', value:'EXPIRED' }], sortField: 'expiration_date', sortDirection: 'asc' } },
  { key: 'pending-credential-verification', name: 'Pending Credential Verification', description: 'Credential renewal submissions awaiting administrative review.', definition: { dataSource: 'credential_submissions', columns: ['provider_name','agencies','credential_name','status','expiration_date','submitted_at'], filters: [{ field:'status', operator:'equals', value:'pending' }], sortField: 'submitted_at', sortDirection: 'asc' } },
  { key: 'provider-credential-history', name: 'Provider Credential History', description: 'Historical credential records, including superseded credentials.', definition: { dataSource: 'credential_history', columns: ['provider_name','agencies','credential_name','credential_number','issue_date','expiration_date','verification_status','is_current'], filters: [], sortField: 'provider_name', sortDirection: 'asc' } },
  { key: 'credential-type-census', name: 'Credential Type Census', description: 'Counts of current, expiring and expired records by credential type.', definition: { dataSource: 'credential_type_census', columns: ['credential_name','category','scope','active_records','expiring_90_days','expired_records'], filters: [], sortField: 'credential_name', sortDirection: 'asc' } },
  { key: 'vehicle-operations-overview', name: 'Vehicle & Inspection Operations', description: 'One row per vehicle combining fleet details, inspection compliance, latest inspection, and deficiency counts.', definition: { dataSource: 'vehicle_operations', columns: ['agency','unit_number','vehicle_type','vehicle_status','inspection_compliance_status','next_inspection_due','latest_inspection_date','latest_inspection_result','open_deficiency_count','critical_deficiency_count'], filters: [], sortField: 'agency', sortDirection: 'asc', groupField: 'agency' } },
  { key: 'provider-operations-overview', name: 'Provider Compliance & CE Overview', description: 'One row per provider with Personnel plus Credential and CE summaries as those modules are enabled.', definition: { dataSource: 'provider_operations', columns: ['provider_name','provider_number','provider_level','agencies','credential_issue_count','pending_credential_submissions','ce_hours_12_months','latest_ce_date'], filters: [], sortField: 'provider_name', sortDirection: 'asc' } },
  { key: 'fleet-roster', name: 'Fleet Roster', description: 'Active system and agency vehicle roster.', definition: { dataSource: 'fleet', columns: ['agency','unit_number','fleet_number','vehicle_type','vehicle_status','year','make','model','license_plate'], filters: [], sortField: 'agency', sortDirection: 'asc', groupField: 'agency' } },
  { key: 'vehicle-license-expiration', name: 'Vehicle License Expiration', description: 'Required vehicle licensing and expiration status.', definition: { dataSource: 'vehicle_license_compliance', columns: ['agency','unit_number','license_name','expiration_date','compliance_status','days_remaining'], filters: [], sortField: 'expiration_date', sortDirection: 'asc' } },
  { key: 'upcoming-inspections', name: 'Upcoming / Overdue Inspections', description: 'Inspection due dates and current inspection compliance.', definition: { dataSource: 'inspection_compliance', columns: ['agency','unit_number','inspection_name','latest_inspection_date','latest_result','next_due_date','compliance_status','days_until_due'], filters: [{ field:'compliance_status', operator:'not_equals', value:'CURRENT' }], sortField: 'next_due_date', sortDirection: 'asc' } },
  { key: 'inspection-history', name: 'Inspection History', description: 'Submitted vehicle inspections visible within your administrative scope.', definition: { dataSource: 'inspection_history', columns: ['inspection_date','agency','unit_number','inspection_type','result','inspector_name','submitted_at'], filters: [{ field:'workflow_status', operator:'equals', value:'submitted' }], sortField: 'inspection_date', sortDirection: 'desc' } },
  { key: 'open-inspection-deficiencies', name: 'Open Inspection Deficiencies', description: 'Vehicle inspection deficiencies that have not been closed.', definition: { dataSource: 'inspection_deficiencies', columns: ['inspection_date','agency','unit_number','description','severity','status','correction_due_date'], filters: [{ field:'status', operator:'equals', value:'open' }], sortField: 'correction_due_date', sortDirection: 'asc' } },
  { key: 'ce-completion-history', name: 'CE Completion History', description: 'Verified instructor-led and approved external CE completion history.', definition: { dataSource: 'ce_completions', columns: ['provider_name','agencies','completion_date','course_title','category','delivery_source','credit_hours','verification_method'], filters: [], sortField: 'completion_date', sortDirection: 'desc' } },
  { key: 'ce-session-attendance', name: 'CE Session Attendance', description: 'Scheduled CE attendance showing check-in and completion status.', definition: { dataSource: 'ce_attendance_history', columns: ['provider_name','agencies','session_date','course_title','location','attendance_status','checked_in_at','verified_at','credit_hours'], filters: [], sortField: 'session_date', sortDirection: 'desc' } },
  { key: 'narcotics-count-history', name: 'Narcotics Count History', description: 'Submitted daily narcotics count history, including seal changes and discrepancies.', definition: { dataSource: 'narcotics_history', columns: ['count_date','agency','unit_number','form_name','seal_number','prior_seal_number','signed_name','signed_at','has_discrepancy'], filters: [], sortField: 'count_date', sortDirection: 'desc' } },
  { key: 'system-compliance-summary', name: 'System Compliance Summary', description: 'System-wide compliance summary by agency for personnel, credentials, fleet and inspections.', definition: { dataSource: 'agency_compliance_summary', columns: ['agency','active_providers','credential_issues','active_vehicles','vehicle_license_issues','inspection_issues','open_deficiencies'], filters: [], sortField: 'agency', sortDirection: 'asc' } },
  { key: 'agency-compliance-summary', name: 'Agency Compliance Summary', description: 'High-level personnel, credential, fleet and inspection compliance by agency.', definition: { dataSource: 'agency_compliance_summary', columns: ['agency','active_providers','credential_issues','active_vehicles','vehicle_license_issues','inspection_issues','open_deficiencies'], filters: [], sortField: 'agency', sortDirection: 'asc' } },
]

export function sourceFor(key: string) { return REPORT_SOURCES.find((source) => source.key === key) }
export function builtInFor(key: string) { return BUILTIN_REPORTS.find((report) => report.key === key) }
