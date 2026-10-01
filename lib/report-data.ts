import type { SupabaseClient } from '@supabase/supabase-js'
import { sourceAvailableForModules, sourceFor, sourceRequiredModules, type ReportDefinition, type ReportField, type ReportFilter } from './report-catalog'
import { enabledModuleKeys, getModuleStates, moduleLabel, type ModuleKey } from './modules'

export type ReportRow = Record<string, any>
export type CustomReportField = ReportField & { customFieldId?: string }
export type ReportScope = { isSystemAdmin: boolean; agencyIds: string[] }

function one<T = any>(value: T | T[] | null | undefined): T | null {
  return Array.isArray(value) ? (value[0] ?? null) : (value ?? null)
}
function displayAgency(agency: any) { return agency?.short_name || agency?.name || '' }
function fullName(provider: any) { return [provider?.last_name, provider?.first_name].filter(Boolean).join(', ') }
function dateInZone(value: string | null | undefined, timeZone = 'America/Chicago') {
  if (!value) return ''
  const parts = Object.fromEntries(new Intl.DateTimeFormat('en-US', { timeZone, year:'numeric', month:'2-digit', day:'2-digit' }).formatToParts(new Date(value)).filter((p) => p.type !== 'literal').map((p) => [p.type, p.value]))
  return `${parts.year}-${parts.month}-${parts.day}`
}
function agencyScope(scope?: ReportScope) { return scope && !scope.isSystemAdmin ? scope.agencyIds : null }

async function allowedProviderIds(supabase: SupabaseClient, scope?: ReportScope) {
  const ids = agencyScope(scope)
  if (ids === null) return null
  if (!ids.length) return []
  const { data: activeAgencies, error: agencyError } = await supabase.from('agencies').select('id').in('id', ids).eq('active', true)
  if (agencyError) throw agencyError
  const activeIds = (activeAgencies ?? []).map((row: any) => row.id)
  if (!activeIds.length) return []
  const { data, error } = await supabase.from('provider_agencies').select('provider_id').in('agency_id', activeIds).eq('active', true)
  if (error) throw error
  return [...new Set((data ?? []).map((row: any) => row.provider_id))]
}

async function affiliationMap(supabase: SupabaseClient, providerIds: string[], scope?: ReportScope) {
  const out = new Map<string, { names: string[]; primary: string }>()
  if (!providerIds.length) return out
  let query = supabase.from('provider_agencies').select('provider_id, agency_id, is_primary, agencies(id, name, short_name, active)').in('provider_id', providerIds).eq('active', true)
  const ids = agencyScope(scope)
  if (ids !== null) {
    if (!ids.length) return out
    query = query.in('agency_id', ids)
  }
  const { data, error } = await query
  if (error) throw error
  for (const row of data ?? []) {
    const agency = one<any>(row.agencies)
    if (agency?.active !== true) continue
    const agencyName = displayAgency(agency)
    if (!out.has(row.provider_id)) out.set(row.provider_id, { names: [], primary: '' })
    const item = out.get(row.provider_id)!
    if (agencyName) item.names.push(agencyName)
    if (row.is_primary && agencyName) item.primary = agencyName
  }
  for (const item of out.values()) if (!item.primary) item.primary = item.names[0] || ''
  return out
}

async function agencyMap(supabase: SupabaseClient, scope?: ReportScope) {
  let query = supabase.from('agencies').select('id, name, short_name').eq('active', true)
  const ids = agencyScope(scope)
  if (ids !== null) {
    if (!ids.length) return new Map<string, string>()
    query = query.in('id', ids)
  }
  const { data, error } = await query
  if (error) throw error
  return new Map((data ?? []).map((row: any) => [row.id, displayAgency(row)]))
}

async function providerContext(supabase: SupabaseClient, providerIds: string[], scope?: ReportScope) {
  if (!providerIds.length) return new Map<string, any>()
  const { data, error } = await supabase.from('providers').select('id, first_name, last_name, provider_levels(name, code)').in('id', providerIds)
  if (error) throw error
  const affiliations = await affiliationMap(supabase, providerIds, scope)
  const map = new Map<string, any>()
  for (const provider of data ?? []) {
    const aff = affiliations.get(provider.id) || { names: [], primary: '' }
    map.set(provider.id, {
      provider_name: fullName(provider),
      provider_level: one<any>(provider.provider_levels)?.name || '',
      agencies: aff.names.join(', '),
      primary_agency: aff.primary,
    })
  }
  return map
}

async function loadCustomFields(supabase: SupabaseClient, entityType: 'provider' | 'agency' | 'vehicle', module?: ModuleKey) {
  const { data: defs } = await supabase.from('record_field_definitions').select('id, label, field_type, field_key, sort_order').eq('entity_type', entityType).eq('source_type', 'custom').eq('enabled', true).order('sort_order')
  return (defs ?? []).map((def: any): CustomReportField => ({
    key: `custom:${def.id}`,
    label: def.label,
    type: def.field_type === 'number' ? 'number' : def.field_type === 'date' ? 'date' : def.field_type === 'boolean' ? 'boolean' : 'text',
    customFieldId: def.id,
    module,
  }))
}

export async function reportFieldsForSource(supabase: SupabaseClient, sourceKey: string, enabledModules?: Set<ModuleKey>) {
  const base = sourceFor(sourceKey)?.fields ?? []
  let fields: CustomReportField[] = [...base]
  if (sourceKey === 'personnel') fields = [...fields, ...(await loadCustomFields(supabase, 'provider', 'personnel'))]
  if (sourceKey === 'agencies') fields = [...fields, ...(await loadCustomFields(supabase, 'agency'))]
  if (sourceKey === 'fleet') fields = [...fields, ...(await loadCustomFields(supabase, 'vehicle', 'fleet'))]
  if (sourceKey === 'vehicle_operations') fields = [...fields, ...(await loadCustomFields(supabase, 'vehicle', 'fleet'))]
  if (sourceKey === 'provider_operations') fields = [...fields, ...(await loadCustomFields(supabase, 'provider', 'personnel'))]

  const enabled = enabledModules ?? new Set(enabledModuleKeys(await getModuleStates(supabase)))
  return fields.filter((field) => !field.module || enabled.has(field.module))
}

async function addCustomValues(supabase: SupabaseClient, rows: ReportRow[], entityIds: string[], fields: CustomReportField[]) {
  const custom = fields.filter((field) => field.customFieldId)
  if (!custom.length || !entityIds.length) return rows
  const ids = custom.map((field) => field.customFieldId!)
  const { data } = await supabase.from('record_custom_field_values').select('field_definition_id, entity_id, value').in('field_definition_id', ids).in('entity_id', entityIds)
  const values = new Map<string, any>()
  for (const value of data ?? []) values.set(`${value.entity_id}:${value.field_definition_id}`, value.value)
  return rows.map((row: any) => {
    const out = { ...row }
    for (const field of custom) {
      const raw = values.get(`${row.__entity_id}:${field.customFieldId}`)
      if (Array.isArray(raw)) out[field.key] = raw.join(', ')
      else if (typeof raw === 'boolean' || typeof raw === 'number') out[field.key] = raw
      else if (raw == null) out[field.key] = null
      else if (typeof raw === 'object') out[field.key] = JSON.stringify(raw)
      else out[field.key] = String(raw)
    }
    return out
  })
}

async function personnelRows(supabase: SupabaseClient, fields: CustomReportField[], scope?: ReportScope): Promise<ReportRow[]> {
  const permitted = await allowedProviderIds(supabase, scope)
  if (permitted !== null && permitted.length === 0) return []
  let query = supabase.from('providers').select('id, provider_number, first_name, middle_name, last_name, preferred_name, email, phone, system_entry_date, provider_levels(name, code), provider_statuses(name, code)').order('last_name').limit(5000)
  if (permitted !== null) query = query.in('id', permitted)
  const { data, error } = await query
  if (error) throw error
  const ids = (data ?? []).map((p: any) => p.id)
  const affiliations = await affiliationMap(supabase, ids, scope)
  let rows: ReportRow[] = (data ?? []).map((provider: any) => {
    const aff = affiliations.get(provider.id) || { names: [], primary: '' }
    return {
      __entity_id: provider.id,
      provider_name: fullName(provider), provider_number: provider.provider_number, first_name: provider.first_name,
      middle_name: provider.middle_name, last_name: provider.last_name, preferred_name: provider.preferred_name,
      provider_level: one<any>(provider.provider_levels)?.name || '', provider_status: one<any>(provider.provider_statuses)?.name || '',
      agencies: aff.names.join(', '), primary_agency: aff.primary, email: provider.email, phone: provider.phone,
      system_entry_date: provider.system_entry_date, active_agency_count: aff.names.length,
    }
  })
  rows = await addCustomValues(supabase, rows, ids, fields)
  return rows
}

async function agencyRows(supabase: SupabaseClient, fields: CustomReportField[], scope?: ReportScope): Promise<ReportRow[]> {
  let query = supabase.from('agencies').select('id, name, short_name, active').eq('active', true).order('name').limit(1000)
  const allowed = agencyScope(scope)
  if (allowed !== null) {
    if (!allowed.length) return []
    query = query.in('id', allowed)
  }
  const { data, error } = await query
  if (error) throw error
  const ids = (data ?? []).map((agency: any) => agency.id)
  const needsProviderCount = fields.some((field) => field.key === 'provider_count')
  const needsVehicleCount = fields.some((field) => field.key === 'vehicle_count')
  const [{ data: memberships }, { data: vehicles }] = await Promise.all([
    needsProviderCount && ids.length ? supabase.from('provider_agencies').select('agency_id').in('agency_id', ids).eq('active', true) : Promise.resolve({ data: [] } as any),
    needsVehicleCount && ids.length ? supabase.from('vehicles').select('agency_id').in('agency_id', ids).eq('active', true) : Promise.resolve({ data: [] } as any),
  ])
  const providers = new Map<string, number>(); const fleet = new Map<string, number>()
  for (const row of memberships ?? []) providers.set(row.agency_id, (providers.get(row.agency_id) ?? 0) + 1)
  for (const row of vehicles ?? []) fleet.set(row.agency_id, (fleet.get(row.agency_id) ?? 0) + 1)
  let rows: ReportRow[] = (data ?? []).map((agency: any) => ({ __entity_id: agency.id, agency_name: agency.name, short_name: agency.short_name, active: agency.active, provider_count: providers.get(agency.id) ?? 0, vehicle_count: fleet.get(agency.id) ?? 0 }))
  rows = await addCustomValues(supabase, rows, ids, fields)
  return rows
}

async function credentialComplianceRows(supabase: SupabaseClient, scope?: ReportScope): Promise<ReportRow[]> {
  const permitted = await allowedProviderIds(supabase, scope)
  if (permitted !== null && permitted.length === 0) return []
  let query = supabase.from('provider_compliance').select('*').limit(10000)
  if (permitted !== null) query = query.in('provider_id', permitted)
  const { data, error } = await query
  if (error) throw error
  const allowedAgencies = agencyScope(scope)
  const filtered = (data ?? []).filter((row: any) => allowedAgencies === null || row.credential_scope_type === 'system' || allowedAgencies.includes(row.credential_agency_id))
  const ids = [...new Set(filtered.map((row: any) => row.provider_id))]
  const ctx = await providerContext(supabase, ids, scope)
  return filtered.map((row: any) => ({
    provider_name: ctx.get(row.provider_id)?.provider_name || [row.last_name,row.first_name].filter(Boolean).join(', '), agencies: ctx.get(row.provider_id)?.agencies || '',
    provider_level: ctx.get(row.provider_id)?.provider_level || '', credential_name: row.credential_name,
    credential_scope: row.credential_scope_type === 'agency' ? 'Agency' : 'System', expiration_date: row.expiration_date,
    compliance_status: row.compliance_status, days_remaining: row.days_remaining,
  }))
}

async function credentialRecordRows(supabase: SupabaseClient, scope?: ReportScope): Promise<ReportRow[]> {
  const permitted = await allowedProviderIds(supabase, scope)
  if (permitted !== null && permitted.length === 0) return []
  let query = supabase.from('provider_credentials').select('provider_id, credential_number, issue_date, expiration_date, source, credential_types(name, category, scope_type, agency_id, warning_days)').eq('is_current', true).eq('verification_status', 'verified').limit(10000)
  if (permitted !== null) query = query.in('provider_id', permitted)
  const { data, error } = await query
  if (error) throw error
  const allowedAgencies = agencyScope(scope)
  const filtered = (data ?? []).filter((row: any) => { const ct = one<any>(row.credential_types); return allowedAgencies === null || ct?.scope_type === 'system' || allowedAgencies.includes(ct?.agency_id) })
  const ids = [...new Set(filtered.map((row: any) => row.provider_id))]
  const ctx = await providerContext(supabase, ids, scope)
  const today = new Date(); today.setHours(0,0,0,0)
  return filtered.map((row: any) => {
    const ct = one<any>(row.credential_types); const exp = row.expiration_date ? new Date(`${row.expiration_date}T00:00:00`) : null
    const days = exp ? Math.round((exp.getTime() - today.getTime()) / 86400000) : null
    const warning = Math.max(...((ct?.warning_days ?? [90]) as number[]))
    const status = days === null ? 'CURRENT' : days < 0 ? 'EXPIRED' : days <= warning ? 'EXPIRING_SOON' : 'CURRENT'
    return { provider_name: ctx.get(row.provider_id)?.provider_name || '', agencies: ctx.get(row.provider_id)?.agencies || '', credential_name: ct?.name || '', category: ct?.category || '', credential_number: row.credential_number, issue_date: row.issue_date, expiration_date: row.expiration_date, status, days_remaining: days, source: row.source }
  })
}

async function credentialHistoryRows(supabase: SupabaseClient, scope?: ReportScope): Promise<ReportRow[]> {
  const permitted = await allowedProviderIds(supabase, scope)
  if (permitted !== null && permitted.length === 0) return []
  let query = supabase.from('provider_credentials').select('provider_id, credential_number, issue_date, expiration_date, verification_status, is_current, source, created_at, credential_types(name, scope_type, agency_id)').order('created_at', { ascending: false }).limit(10000)
  if (permitted !== null) query = query.in('provider_id', permitted)
  const { data, error } = await query
  if (error) throw error
  const allowedAgencies = agencyScope(scope)
  const filtered = (data ?? []).filter((row: any) => { const ct = one<any>(row.credential_types); return allowedAgencies === null || ct?.scope_type === 'system' || allowedAgencies.includes(ct?.agency_id) })
  const ids = [...new Set(filtered.map((r: any) => r.provider_id))]
  const ctx = await providerContext(supabase, ids, scope)
  return filtered.map((row: any) => ({ provider_name: ctx.get(row.provider_id)?.provider_name || '', agencies: ctx.get(row.provider_id)?.agencies || '', credential_name: one<any>(row.credential_types)?.name || '', credential_number: row.credential_number, issue_date: row.issue_date, expiration_date: row.expiration_date, verification_status: row.verification_status, is_current: row.is_current, source: row.source, created_at: row.created_at }))
}

async function credentialSubmissionRows(supabase: SupabaseClient, scope?: ReportScope): Promise<ReportRow[]> {
  const permitted = await allowedProviderIds(supabase, scope)
  if (permitted !== null && permitted.length === 0) return []
  let query = supabase.from('credential_submissions').select('provider_id, credential_number, expiration_date, status, submitted_at, reviewed_at, review_notes, credential_types(name, scope_type, agency_id)').order('submitted_at', { ascending: false }).limit(10000)
  if (permitted !== null) query = query.in('provider_id', permitted)
  const { data, error } = await query
  if (error) throw error
  const allowedAgencies = agencyScope(scope)
  const filtered = (data ?? []).filter((row: any) => { const ct = one<any>(row.credential_types); return allowedAgencies === null || ct?.scope_type === 'system' || allowedAgencies.includes(ct?.agency_id) })
  const ids = [...new Set(filtered.map((r: any) => r.provider_id))]
  const ctx = await providerContext(supabase, ids, scope)
  return filtered.map((row: any) => ({ provider_name: ctx.get(row.provider_id)?.provider_name || '', agencies: ctx.get(row.provider_id)?.agencies || '', credential_name: one<any>(row.credential_types)?.name || '', status: row.status, credential_number: row.credential_number, expiration_date: row.expiration_date, submitted_at: row.submitted_at, reviewed_at: row.reviewed_at, review_notes: row.review_notes }))
}

async function credentialTypeCensusRows(supabase: SupabaseClient, scope?: ReportScope): Promise<ReportRow[]> {
  const allowedAgencies = agencyScope(scope)
  let typeQuery = supabase.from('credential_types').select('id, name, category, scope_type, agency_id').eq('active', true)
  const { data: types, error } = await typeQuery
  if (error) throw error
  const available = (types ?? []).filter((ct: any) => allowedAgencies === null || ct.scope_type === 'system' || allowedAgencies.includes(ct.agency_id))
  if (!available.length) return []
  const permitted = await allowedProviderIds(supabase, scope)
  if (permitted !== null && permitted.length === 0) return available.map((ct: any) => ({ credential_name: ct.name, category: ct.category, scope: ct.scope_type === 'system' ? 'System' : 'Agency', active_records: 0, expiring_90_days: 0, expired_records: 0 }))
  let q = supabase.from('provider_credentials').select('credential_type_id, provider_id, expiration_date').eq('is_current', true).eq('verification_status', 'verified').in('credential_type_id', available.map((ct: any) => ct.id)).limit(20000)
  if (permitted !== null) q = q.in('provider_id', permitted)
  const { data: records, error: recError } = await q
  if (recError) throw recError
  const today = new Date(); today.setHours(0,0,0,0); const ninety = new Date(today.getTime() + 90*86400000)
  return available.map((ct: any) => {
    const list = (records ?? []).filter((r: any) => r.credential_type_id === ct.id)
    let expired = 0, expiring = 0
    for (const r of list) if (r.expiration_date) { const d = new Date(`${r.expiration_date}T00:00:00`); if (d < today) expired++; else if (d <= ninety) expiring++ }
    return { credential_name: ct.name, category: ct.category, scope: ct.scope_type === 'system' ? 'System' : 'Agency', active_records: list.length, expiring_90_days: expiring, expired_records: expired }
  })
}

async function fleetRows(supabase: SupabaseClient, fields: CustomReportField[], scope?: ReportScope): Promise<ReportRow[]> {
  let query = supabase.from('vehicles').select('id, agency_id, unit_number, fleet_number, vin, year, make, model, license_plate, license_plate_state, in_service_date, narcotics_count_required, agencies(name, short_name, active), vehicle_types(name, code), vehicle_statuses(name, code)').eq('active', true).order('unit_number').limit(5000)
  const allowed = agencyScope(scope)
  if (allowed !== null) { if (!allowed.length) return []; query = query.in('agency_id', allowed) }
  const { data, error } = await query
  if (error) throw error
  const activeVehicles = (data ?? []).filter((vehicle: any) => one<any>(vehicle.agencies)?.active === true)
  let rows: ReportRow[] = activeVehicles.map((vehicle: any) => ({ __entity_id: vehicle.id, agency: displayAgency(one(vehicle.agencies)), unit_number: vehicle.unit_number, fleet_number: vehicle.fleet_number, vehicle_type: one<any>(vehicle.vehicle_types)?.name || '', vehicle_status: one<any>(vehicle.vehicle_statuses)?.name || '', vin: vehicle.vin, year: vehicle.year, make: vehicle.make, model: vehicle.model, license_plate: vehicle.license_plate, license_plate_state: vehicle.license_plate_state, in_service_date: vehicle.in_service_date, narcotics_count_required: vehicle.narcotics_count_required }))
  rows = await addCustomValues(supabase, rows, activeVehicles.map((vehicle: any) => vehicle.id), fields)
  return rows
}


async function vehicleOperationsRows(
  supabase: SupabaseClient,
  fields: CustomReportField[],
  scope: ReportScope | undefined,
  enabledModules: Set<ModuleKey>
): Promise<ReportRow[]> {
  const rows = await fleetRows(supabase, fields, scope)
  const ids = rows.map((row: any) => row.__entity_id).filter(Boolean)
  if (!ids.length) return rows

  const [complianceResult, historyResult, deficienciesResult, narcoticsResult] = await Promise.all([
    supabase
      .from('vehicle_inspection_compliance')
      .select('vehicle_id, inspection_name, latest_inspection_date, latest_result, next_due_date, compliance_status, days_until_due')
      .in('vehicle_id', ids)
      .limit(20000),
    supabase
      .from('vehicle_inspections')
      .select('vehicle_id, inspection_date, result, inspector_name, submitted_at, inspection_types(name)')
      .in('vehicle_id', ids)
      .eq('workflow_status', 'submitted')
      .order('inspection_date', { ascending: false })
      .order('submitted_at', { ascending: false })
      .limit(20000),
    supabase
      .from('vehicle_inspection_deficiencies')
      .select('severity, status, vehicle_inspections(vehicle_id, workflow_status)')
      .eq('status', 'open')
      .limit(20000),
    enabledModules.has('narcotics')
      ? supabase
          .from('narcotics_counts')
          .select('vehicle_id, count_date, seal_number, signed_name, has_discrepancy')
          .in('vehicle_id', ids)
          .eq('status', 'submitted')
          .order('count_date', { ascending: false })
          .order('signed_at', { ascending: false })
          .limit(20000)
      : Promise.resolve({ data: [] as any[], error: null } as any),
  ])

  if (complianceResult.error) throw complianceResult.error
  if (historyResult.error) throw historyResult.error
  if (deficienciesResult.error) throw deficienciesResult.error
  if (narcoticsResult.error) throw narcoticsResult.error

  const statusRank: Record<string, number> = {
    FAILED: 60,
    OVERDUE: 50,
    MISSING: 40,
    SCHEDULE_MISSING: 35,
    DUE_SOON: 20,
    CURRENT: 10,
  }

  const inspection = new Map<string, any>()
  for (const item of complianceResult.data ?? []) {
    const current = inspection.get(item.vehicle_id) || {
      requirementCount: 0,
      issueCount: 0,
      overdueCount: 0,
      failedCount: 0,
      missingCount: 0,
      worstStatus: '',
      worstRank: -1,
      nextDue: null as string | null,
    }
    current.requirementCount += 1
    if (item.compliance_status !== 'CURRENT') current.issueCount += 1
    if (item.compliance_status === 'OVERDUE') current.overdueCount += 1
    if (item.compliance_status === 'FAILED') current.failedCount += 1
    if (item.compliance_status === 'MISSING' || item.compliance_status === 'SCHEDULE_MISSING') current.missingCount += 1
    const rank = statusRank[item.compliance_status] ?? 0
    if (rank > current.worstRank) {
      current.worstRank = rank
      current.worstStatus = item.compliance_status
    }
    if (item.next_due_date && (!current.nextDue || item.next_due_date < current.nextDue)) current.nextDue = item.next_due_date
    inspection.set(item.vehicle_id, current)
  }

  const latestInspection = new Map<string, any>()
  for (const item of historyResult.data ?? []) {
    if (!latestInspection.has(item.vehicle_id)) latestInspection.set(item.vehicle_id, item)
  }

  const deficiency = new Map<string, { open: number; critical: number }>()
  const idSet = new Set(ids)
  for (const item of deficienciesResult.data ?? []) {
    const vi = one<any>(item.vehicle_inspections)
    if (!vi?.vehicle_id || !idSet.has(vi.vehicle_id) || vi.workflow_status !== 'submitted') continue
    const current = deficiency.get(vi.vehicle_id) || { open: 0, critical: 0 }
    current.open += 1
    if (item.severity === 'critical') current.critical += 1
    deficiency.set(vi.vehicle_id, current)
  }

  const latestNarcotics = new Map<string, any>()
  for (const item of narcoticsResult.data ?? []) {
    if (!latestNarcotics.has(item.vehicle_id)) latestNarcotics.set(item.vehicle_id, item)
  }

  return rows.map((row: any) => {
    const id = row.__entity_id
    const compliance = inspection.get(id) || {}
    const latest = latestInspection.get(id)
    const deficiencies = deficiency.get(id) || { open: 0, critical: 0 }
    const narcotics = latestNarcotics.get(id)

    return {
      ...row,
      inspection_requirement_count: compliance.requirementCount ?? 0,
      inspection_issue_count: compliance.issueCount ?? 0,
      inspection_compliance_status: compliance.worstStatus || (compliance.requirementCount ? 'CURRENT' : 'NO REQUIREMENT'),
      next_inspection_due: compliance.nextDue ?? null,
      latest_inspection_date: latest?.inspection_date ?? null,
      latest_inspection_type: one<any>(latest?.inspection_types)?.name || '',
      latest_inspection_result: latest?.result ?? null,
      latest_inspector: latest?.inspector_name ?? '',
      overdue_inspection_count: compliance.overdueCount ?? 0,
      failed_inspection_count: compliance.failedCount ?? 0,
      missing_inspection_count: compliance.missingCount ?? 0,
      open_deficiency_count: deficiencies.open,
      critical_deficiency_count: deficiencies.critical,
      latest_narcotics_count_date: narcotics?.count_date ?? null,
      latest_narcotics_seal: narcotics?.seal_number ?? '',
      latest_narcotics_signed_by: narcotics?.signed_name ?? '',
      latest_narcotics_discrepancy: narcotics?.has_discrepancy ?? null,
    }
  })
}

async function providerOperationsRows(
  supabase: SupabaseClient,
  fields: CustomReportField[],
  scope: ReportScope | undefined,
  enabledModules: Set<ModuleKey>
): Promise<ReportRow[]> {
  const rows = await personnelRows(supabase, fields, scope)
  const ids = rows.map((row: any) => row.__entity_id).filter(Boolean)
  if (!ids.length) return rows

  const credentialEnabled = enabledModules.has('credentials')
  const ceEnabled = enabledModules.has('ce')

  const [complianceResult, submissionsResult, ceAttendanceResult, ceExternalResult] = await Promise.all([
    credentialEnabled
      ? supabase.from('provider_compliance').select('provider_id, expiration_date, compliance_status').in('provider_id', ids).limit(30000)
      : Promise.resolve({ data: [] as any[], error: null } as any),
    credentialEnabled
      ? supabase.from('credential_submissions').select('provider_id, status').in('provider_id', ids).eq('status', 'pending').limit(20000)
      : Promise.resolve({ data: [] as any[], error: null } as any),
    ceEnabled
      ? supabase.from('ce_attendance').select('provider_id, credit_hours_awarded, ce_sessions(start_at, timezone)').in('provider_id', ids).eq('status', 'completed').limit(30000)
      : Promise.resolve({ data: [] as any[], error: null } as any),
    ceEnabled
      ? supabase.from('ce_external_submissions').select('provider_id, completion_date, credit_hours, status').in('provider_id', ids).in('status', ['approved','pending']).limit(30000)
      : Promise.resolve({ data: [] as any[], error: null } as any),
  ])

  for (const result of [complianceResult, submissionsResult, ceAttendanceResult, ceExternalResult]) {
    if (result.error) throw result.error
  }

  const credentials = new Map<string, any>()
  for (const item of complianceResult.data ?? []) {
    const current = credentials.get(item.provider_id) || {
      required: 0, issues: 0, missing: 0, expired: 0, expiring: 0, pending: 0, nextExpiration: null as string | null,
    }
    current.required += 1
    if (item.compliance_status !== 'CURRENT') current.issues += 1
    if (item.compliance_status === 'MISSING') current.missing += 1
    if (item.compliance_status === 'EXPIRED') current.expired += 1
    if (item.compliance_status === 'EXPIRING_SOON') current.expiring += 1
    if (item.expiration_date && (!current.nextExpiration || item.expiration_date < current.nextExpiration)) current.nextExpiration = item.expiration_date
    credentials.set(item.provider_id, current)
  }
  for (const item of submissionsResult.data ?? []) {
    const current = credentials.get(item.provider_id) || {
      required: 0, issues: 0, missing: 0, expired: 0, expiring: 0, pending: 0, nextExpiration: null as string | null,
    }
    current.pending += 1
    credentials.set(item.provider_id, current)
  }

  const ce = new Map<string, any>()
  const cutoff = new Date()
  cutoff.setFullYear(cutoff.getFullYear() - 1)
  const cutoffDate = cutoff.toISOString().slice(0, 10)

  function addCE(providerId: string, completionDate: string | null, hours: number, approved = true) {
    const current = ce.get(providerId) || { total: 0, last12: 0, completions: 0, latest: null as string | null, pending: 0 }
    if (!approved) {
      current.pending += 1
      ce.set(providerId, current)
      return
    }
    current.total += hours
    current.completions += 1
    if (completionDate && completionDate >= cutoffDate) current.last12 += hours
    if (completionDate && (!current.latest || completionDate > current.latest)) current.latest = completionDate
    ce.set(providerId, current)
  }

  for (const item of ceAttendanceResult.data ?? []) {
    const session = one<any>(item.ce_sessions)
    addCE(item.provider_id, session?.start_at ? dateInZone(session.start_at, session?.timezone || 'America/Chicago') : null, Number(item.credit_hours_awarded || 0))
  }
  for (const item of ceExternalResult.data ?? []) {
    if (item.status === 'pending') addCE(item.provider_id, item.completion_date, 0, false)
    else addCE(item.provider_id, item.completion_date, Number(item.credit_hours || 0))
  }

  return rows.map((row: any) => {
    const credential = credentials.get(row.__entity_id) || {}
    const education = ce.get(row.__entity_id) || {}
    return {
      ...row,
      required_credential_count: credential.required ?? 0,
      credential_issue_count: credential.issues ?? 0,
      missing_credential_count: credential.missing ?? 0,
      expired_credential_count: credential.expired ?? 0,
      expiring_credential_count: credential.expiring ?? 0,
      pending_credential_submissions: credential.pending ?? 0,
      next_credential_expiration: credential.nextExpiration ?? null,
      ce_total_hours: Number(education.total ?? 0),
      ce_hours_12_months: Number(education.last12 ?? 0),
      ce_completion_count: education.completions ?? 0,
      latest_ce_date: education.latest ?? null,
      pending_external_ce: education.pending ?? 0,
    }
  })
}

async function vehicleLicenseRows(supabase: SupabaseClient, scope?: ReportScope): Promise<ReportRow[]> {
  let query = supabase.from('vehicle_license_compliance').select('*').limit(10000)
  const allowed = agencyScope(scope); if (allowed !== null) { if (!allowed.length) return []; query = query.in('agency_id', allowed) }
  const [licenses, agencies] = await Promise.all([query, agencyMap(supabase, scope)])
  if (licenses.error) throw licenses.error
  return (licenses.data ?? []).map((row: any) => ({ agency: agencies.get(row.agency_id) || '', unit_number: row.unit_number, license_name: row.license_name, expiration_date: row.expiration_date, compliance_status: row.compliance_status, days_remaining: row.days_remaining }))
}

async function inspectionComplianceRows(supabase: SupabaseClient, scope?: ReportScope): Promise<ReportRow[]> {
  let query = supabase.from('vehicle_inspection_compliance').select('*').limit(10000)
  const allowed = agencyScope(scope); if (allowed !== null) { if (!allowed.length) return []; query = query.in('agency_id', allowed) }
  const [result, agencies] = await Promise.all([query, agencyMap(supabase, scope)])
  if (result.error) throw result.error
  return (result.data ?? []).map((row: any) => ({ agency: agencies.get(row.agency_id) || '', unit_number: row.unit_number, inspection_name: row.inspection_name, latest_inspection_date: row.latest_inspection_date, latest_result: row.latest_result, next_due_date: row.next_due_date, compliance_status: row.compliance_status, days_until_due: row.days_until_due }))
}

async function inspectionHistoryRows(supabase: SupabaseClient, scope?: ReportScope): Promise<ReportRow[]> {
  const { data, error } = await supabase.from('vehicle_inspections').select('id, inspection_date, result, workflow_status, inspector_name, inspection_location, odometer, submitted_at, vehicles(active, agency_id, unit_number, fleet_number, agencies(name, short_name, active)), inspection_types(name)').order('inspection_date', { ascending: false }).limit(10000)
  if (error) throw error
  const allowed = agencyScope(scope)
  return (data ?? []).filter((row: any) => { const vehicle = one<any>(row.vehicles); return vehicle?.active === true && one<any>(vehicle?.agencies)?.active === true && (allowed === null || (allowed.includes(vehicle?.agency_id) && row.workflow_status === 'submitted')) }).map((row: any) => { const vehicle = one<any>(row.vehicles); return { inspection_date: row.inspection_date, agency: displayAgency(one(vehicle?.agencies)), unit_number: vehicle?.unit_number || vehicle?.fleet_number || '', inspection_type: one<any>(row.inspection_types)?.name || '', workflow_status: row.workflow_status, result: row.result, inspector_name: row.inspector_name, inspection_location: row.inspection_location, odometer: row.odometer, submitted_at: row.submitted_at } })
}

async function inspectionDeficiencyRows(supabase: SupabaseClient, scope?: ReportScope): Promise<ReportRow[]> {
  const { data, error } = await supabase.from('vehicle_inspection_deficiencies').select('description, severity, status, correction_due_date, corrected_at, correction_notes, vehicle_inspections(inspection_date, workflow_status, vehicles(active, agency_id, unit_number, fleet_number, agencies(name, short_name, active)))').order('created_at', { ascending: false }).limit(10000)
  if (error) throw error
  const allowed = agencyScope(scope)
  return (data ?? []).filter((row: any) => { const inspection = one<any>(row.vehicle_inspections); const vehicle = one<any>(inspection?.vehicles); return vehicle?.active === true && one<any>(vehicle?.agencies)?.active === true && (allowed === null || (allowed.includes(vehicle?.agency_id) && inspection?.workflow_status === 'submitted')) }).map((row: any) => { const inspection = one<any>(row.vehicle_inspections); const vehicle = one<any>(inspection?.vehicles); return { inspection_date: inspection?.inspection_date || null, agency: displayAgency(one(vehicle?.agencies)), unit_number: vehicle?.unit_number || vehicle?.fleet_number || '', description: row.description, severity: row.severity, status: row.status, correction_due_date: row.correction_due_date, corrected_at: row.corrected_at, correction_notes: row.correction_notes } })
}

async function ceCompletionRows(supabase: SupabaseClient, scope?: ReportScope): Promise<ReportRow[]> {
  const permitted = await allowedProviderIds(supabase, scope)
  if (permitted !== null && permitted.length === 0) return []

  let attendanceQuery = supabase.from('ce_attendance').select('provider_id, verified_at, verification_method, credit_hours_awarded, ce_sessions(start_at, timezone, location_name, ce_courses(title, course_code, category))').eq('status', 'completed').limit(20000)
  let externalQuery = supabase.from('ce_external_submissions').select('provider_id, title, sponsor, category, completion_date, credit_hours, reviewed_at').eq('status', 'approved').limit(20000)
  if (permitted !== null) {
    attendanceQuery = attendanceQuery.in('provider_id', permitted)
    externalQuery = externalQuery.in('provider_id', permitted)
  }
  const [attendanceResult, externalResult] = await Promise.all([attendanceQuery, externalQuery])
  if (attendanceResult.error) throw attendanceResult.error
  if (externalResult.error) throw externalResult.error

  const providerIds = [...new Set([...(attendanceResult.data ?? []).map((row:any) => row.provider_id), ...(externalResult.data ?? []).map((row:any) => row.provider_id)])]
  const ctx = await providerContext(supabase, providerIds, scope)
  const rows: ReportRow[] = []
  for (const row of attendanceResult.data ?? []) {
    const session = one<any>(row.ce_sessions); const course = one<any>(session?.ce_courses)
    rows.push({
      provider_name: ctx.get(row.provider_id)?.provider_name || '', agencies: ctx.get(row.provider_id)?.agencies || '',
      completion_date: dateInZone(session?.start_at, session?.timezone || 'America/Chicago'), course_title: course?.title || 'GEAEMS CE Session',
      course_code: course?.course_code || '', category: course?.category || '', delivery_source: 'Instructor-led',
      sponsor_or_location: session?.location_name || 'GEAEMS', credit_hours: Number(row.credit_hours_awarded || 0),
      verification_method: row.verification_method || 'code', verified_at: row.verified_at,
    })
  }
  for (const row of externalResult.data ?? []) rows.push({
    provider_name: ctx.get(row.provider_id)?.provider_name || '', agencies: ctx.get(row.provider_id)?.agencies || '',
    completion_date: row.completion_date, course_title: row.title, course_code: '', category: row.category || '', delivery_source: 'External / online',
    sponsor_or_location: row.sponsor || '', credit_hours: Number(row.credit_hours || 0), verification_method: 'Certificate review', verified_at: row.reviewed_at,
  })
  return rows
}

async function ceAttendanceRows(supabase: SupabaseClient, scope?: ReportScope): Promise<ReportRow[]> {
  const permitted = await allowedProviderIds(supabase, scope)
  if (permitted !== null && permitted.length === 0) return []
  let query = supabase.from('ce_attendance').select('provider_id, status, source, checked_in_at, verified_at, verification_method, credit_hours_awarded, ce_sessions(start_at, timezone, location_name, ce_courses(title, course_code, category))').limit(20000)
  if (permitted !== null) query = query.in('provider_id', permitted)
  const { data, error } = await query
  if (error) throw error
  const providerIds = [...new Set((data ?? []).map((row:any) => row.provider_id))]
  const ctx = await providerContext(supabase, providerIds, scope)
  return (data ?? []).map((row:any) => {
    const session = one<any>(row.ce_sessions); const course = one<any>(session?.ce_courses)
    return {
      provider_name: ctx.get(row.provider_id)?.provider_name || '', agencies: ctx.get(row.provider_id)?.agencies || '',
      session_date: dateInZone(session?.start_at, session?.timezone || 'America/Chicago'), course_title: course?.title || 'GEAEMS CE Session',
      course_code: course?.course_code || '', category: course?.category || '', location: session?.location_name || '',
      attendance_status: row.status, checked_in_at: row.checked_in_at, verified_at: row.verified_at,
      verification_method: row.verification_method || '', entry_source: row.source, credit_hours: row.credit_hours_awarded == null ? null : Number(row.credit_hours_awarded),
    }
  })
}

async function narcoticsRows(supabase: SupabaseClient, scope?: ReportScope): Promise<ReportRow[]> {
  let query = supabase.from('narcotics_counts').select('agency_id, count_date, has_discrepancy, seal_number, prior_seal_number, seal_change_reason, signed_name, signed_at, vehicles(active, unit_number, fleet_number, agencies(name, short_name, active)), narcotics_count_templates(name)').eq('status', 'submitted').order('count_date', { ascending: false }).limit(10000)
  const allowed = agencyScope(scope); if (allowed !== null) { if (!allowed.length) return []; query = query.in('agency_id', allowed) }
  const { data, error } = await query
  if (error) throw error
  return (data ?? []).filter((row: any) => one<any>(row.vehicles)?.active === true && one<any>(one<any>(row.vehicles)?.agencies)?.active === true).map((row: any) => { const vehicle = one<any>(row.vehicles); return { count_date: row.count_date, agency: displayAgency(one(vehicle?.agencies)), unit_number: vehicle?.unit_number || vehicle?.fleet_number || '', form_name: one<any>(row.narcotics_count_templates)?.name || '', seal_number: row.seal_number, prior_seal_number: row.prior_seal_number, seal_change_reason: row.seal_change_reason, signed_name: row.signed_name, signed_at: row.signed_at, has_discrepancy: row.has_discrepancy } })
}

async function agencyComplianceRows(supabase: SupabaseClient, scope?: ReportScope): Promise<ReportRow[]> {
  let agencyQuery = supabase.from('agencies').select('id, name, short_name').eq('active', true).order('name')
  const allowed = agencyScope(scope); if (allowed !== null) { if (!allowed.length) return []; agencyQuery = agencyQuery.in('id', allowed) }
  const { data: agencies, error } = await agencyQuery
  if (error) throw error
  const ids = (agencies ?? []).map((row: any) => row.id)
  if (!ids.length) return []
  const [memberships, vehicles, cred, licenses, inspections, deficiencies] = await Promise.all([
    supabase.from('provider_agencies').select('agency_id, provider_id').in('agency_id', ids).eq('active', true),
    supabase.from('vehicles').select('id, agency_id').in('agency_id', ids).eq('active', true),
    supabase.from('provider_compliance').select('provider_id, compliance_status, credential_scope_type, credential_agency_id').neq('compliance_status', 'CURRENT').limit(10000),
    supabase.from('vehicle_license_compliance').select('agency_id, compliance_status').in('agency_id', ids).neq('compliance_status', 'CURRENT').limit(10000),
    supabase.from('vehicle_inspection_compliance').select('agency_id, compliance_status').in('agency_id', ids).neq('compliance_status', 'CURRENT').limit(10000),
    supabase.from('vehicle_inspection_deficiencies').select('status, vehicle_inspections(workflow_status, vehicles(active, agency_id, agencies(active)))').eq('status', 'open').limit(10000),
  ])
  const providerAgencies = new Map<string, Set<string>>(); const providerCounts = new Map<string, number>()
  for (const row of memberships.data ?? []) { if (!providerAgencies.has(row.provider_id)) providerAgencies.set(row.provider_id, new Set()); providerAgencies.get(row.provider_id)!.add(row.agency_id); providerCounts.set(row.agency_id, (providerCounts.get(row.agency_id) ?? 0) + 1) }
  const fleetCounts = new Map<string, number>(); for (const row of vehicles.data ?? []) fleetCounts.set(row.agency_id, (fleetCounts.get(row.agency_id) ?? 0) + 1)
  const credIssues = new Map<string, number>(); for (const row of cred.data ?? []) for (const agencyId of providerAgencies.get(row.provider_id) ?? []) if (row.credential_scope_type === 'system' || row.credential_agency_id === agencyId) credIssues.set(agencyId, (credIssues.get(agencyId) ?? 0) + 1)
  const licenseIssues = new Map<string, number>(); for (const row of licenses.data ?? []) licenseIssues.set(row.agency_id, (licenseIssues.get(row.agency_id) ?? 0) + 1)
  const inspectionIssues = new Map<string, number>(); for (const row of inspections.data ?? []) inspectionIssues.set(row.agency_id, (inspectionIssues.get(row.agency_id) ?? 0) + 1)
  const deficiencyCounts = new Map<string, number>(); for (const row of deficiencies.data ?? []) { const vi = one<any>(row.vehicle_inspections); const v = one<any>(vi?.vehicles); if (v?.active === true && one<any>(v?.agencies)?.active === true && v?.agency_id && (scope?.isSystemAdmin || vi?.workflow_status === 'submitted')) deficiencyCounts.set(v.agency_id, (deficiencyCounts.get(v.agency_id) ?? 0) + 1) }
  return (agencies ?? []).map((agency: any) => ({ agency: displayAgency(agency), active_providers: providerCounts.get(agency.id) ?? 0, credential_issues: credIssues.get(agency.id) ?? 0, active_vehicles: fleetCounts.get(agency.id) ?? 0, vehicle_license_issues: licenseIssues.get(agency.id) ?? 0, inspection_issues: inspectionIssues.get(agency.id) ?? 0, open_deficiencies: deficiencyCounts.get(agency.id) ?? 0 }))
}

function comparable(value: any) { if (value == null) return ''; if (typeof value === 'boolean') return value ? 'true' : 'false'; return String(value).trim() }
function passes(row: ReportRow, filter: ReportFilter) {
  const left = comparable(row[filter.field]); const right = (filter.value ?? '').trim()
  switch (filter.operator) {
    case 'equals': return left.toLowerCase() === right.toLowerCase()
    case 'not_equals': return left.toLowerCase() !== right.toLowerCase()
    case 'contains': return left.toLowerCase().includes(right.toLowerCase())
    case 'not_contains': return !left.toLowerCase().includes(right.toLowerCase())
    case 'starts_with': return left.toLowerCase().startsWith(right.toLowerCase())
    case 'is_empty': return left === ''
    case 'not_empty': return left !== ''
    case 'one_of': return right.split(',').map((v) => v.trim().toLowerCase()).filter(Boolean).includes(left.toLowerCase())
    case 'gte': return Number(left) >= Number(right)
    case 'lte': return Number(left) <= Number(right)
    case 'after': return left !== '' && left >= right
    case 'before': return left !== '' && left <= right
    default: return true
  }
}
function sortRows(rows: ReportRow[], field?: string, direction: 'asc' | 'desc' = 'asc') {
  if (!field) return rows
  const sign = direction === 'desc' ? -1 : 1
  return [...rows].sort((a, b) => { const av = a[field], bv = b[field]; if (av == null && bv == null) return 0; if (av == null) return 1; if (bv == null) return -1; if (typeof av === 'number' && typeof bv === 'number') return (av-bv)*sign; return String(av).localeCompare(String(bv), undefined, { numeric:true, sensitivity:'base' })*sign })
}

export async function runReport(supabase: SupabaseClient, definition: ReportDefinition, scope?: ReportScope) {
  const moduleStates = await getModuleStates(supabase)
  const enabledModules = new Set(enabledModuleKeys(moduleStates))
  if (!sourceAvailableForModules(definition.dataSource, enabledModules)) {
    const required = sourceRequiredModules(definition.dataSource)
      .filter((module) => !enabledModules.has(module))
      .map(moduleLabel)
      .join(', ')
    throw new Error(`This report dataset is unavailable because these modules are disabled: ${required || 'required module'}.`)
  }

  const fields = await reportFieldsForSource(supabase, definition.dataSource, enabledModules)
  let rows: ReportRow[]
  switch (definition.dataSource) {
    case 'personnel': rows = await personnelRows(supabase, fields, scope); break
    case 'agencies': rows = await agencyRows(supabase, fields, scope); break
    case 'credential_compliance': rows = await credentialComplianceRows(supabase, scope); break
    case 'credential_records': rows = await credentialRecordRows(supabase, scope); break
    case 'credential_history': rows = await credentialHistoryRows(supabase, scope); break
    case 'credential_submissions': rows = await credentialSubmissionRows(supabase, scope); break
    case 'credential_type_census': rows = await credentialTypeCensusRows(supabase, scope); break
    case 'fleet': rows = await fleetRows(supabase, fields, scope); break
    case 'vehicle_operations': rows = await vehicleOperationsRows(supabase, fields, scope, enabledModules); break
    case 'provider_operations': rows = await providerOperationsRows(supabase, fields, scope, enabledModules); break
    case 'vehicle_license_compliance': rows = await vehicleLicenseRows(supabase, scope); break
    case 'inspection_compliance': rows = await inspectionComplianceRows(supabase, scope); break
    case 'inspection_history': rows = await inspectionHistoryRows(supabase, scope); break
    case 'inspection_deficiencies': rows = await inspectionDeficiencyRows(supabase, scope); break
    case 'ce_completions': rows = await ceCompletionRows(supabase, scope); break
    case 'ce_attendance_history': rows = await ceAttendanceRows(supabase, scope); break
    case 'narcotics_history': rows = await narcoticsRows(supabase, scope); break
    case 'agency_compliance_summary': rows = await agencyComplianceRows(supabase, scope); break
    default: throw new Error('Unsupported report data source.')
  }
  const validKeys = new Set(fields.map((field) => field.key))
  const filters = (definition.filters ?? []).filter((filter) => validKeys.has(filter.field))
  rows = rows.filter((row) => filters.every((filter) => passes(row, filter)))
  rows = sortRows(rows, validKeys.has(definition.sortField || '') ? definition.sortField : undefined, definition.sortDirection || 'asc')
  const columns = (definition.columns ?? []).filter((column) => validKeys.has(column))
  return { rows, fields, columns: columns.length ? columns : fields.filter((field) => field.default).map((field) => field.key) }
}

export function csvForReport(rows: ReportRow[], fields: ReportField[], columns: string[]) {
  const labels = new Map(fields.map((field) => [field.key, field.label]))
  const escape = (value: any) => { const text = value == null ? '' : typeof value === 'boolean' ? (value ? 'Yes' : 'No') : String(value); return /[",\n\r]/.test(text) ? `"${text.replace(/"/g, '""')}"` : text }
  return [columns.map((c) => escape(labels.get(c) || c)).join(','), ...rows.map((row) => columns.map((c) => escape(row[c])).join(','))].join('\r\n')
}
