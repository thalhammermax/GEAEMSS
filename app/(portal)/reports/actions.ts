'use server'

import { revalidatePath } from 'next/cache'
import { requireReportAdmin } from '@/lib/report-auth'
import { runReport } from '@/lib/report-data'
import { sourceAvailableForModules, sourceFor, sourceRequiredModules, type ReportDefinition, type ReportFilter } from '@/lib/report-catalog'
import { enabledModuleKeys, getModuleStates, moduleLabel } from '@/lib/modules'

function cleanText(value: unknown, max = 500) {
  return typeof value === 'string' ? value.trim().slice(0, max) : ''
}
function cleanEmailList(values: unknown) {
  if (!Array.isArray(values)) return []
  const emails = values.map((v) => cleanText(v, 320).toLowerCase()).filter(Boolean)
  const valid = emails.filter((v) => /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(v))
  return [...new Set(valid)].slice(0, 25)
}
function normalizeDefinition(input: ReportDefinition): ReportDefinition {
  const source = sourceFor(input?.dataSource)
  if (!source) throw new Error('Choose a valid report data source.')
  const columns = Array.isArray(input.columns) ? input.columns.filter((v): v is string => typeof v === 'string').slice(0, 100) : []
  const filters: ReportFilter[] = Array.isArray(input.filters) ? input.filters.slice(0, 20).map((filter: any) => ({ field: cleanText(filter?.field, 120), operator: cleanText(filter?.operator, 40), value: cleanText(filter?.value, 500) })).filter((filter) => filter.field && filter.operator) : []
  const schedule = input.schedule || {}
  return {
    id: cleanText(input.id, 100) || undefined,
    name: cleanText(input.name, 150),
    description: cleanText(input.description, 1000),
    dataSource: source.key,
    columns,
    filters,
    sortField: cleanText(input.sortField, 120) || undefined,
    sortDirection: input.sortDirection === 'desc' ? 'desc' : 'asc',
    groupField: cleanText(input.groupField, 120) || undefined,
    schedule: {
      enabled: !!schedule.enabled,
      frequency: ['daily','weekly','monthly'].includes(String(schedule.frequency)) ? schedule.frequency : 'daily',
      timezone: cleanText(schedule.timezone, 100) || 'America/Chicago',
      hour: Number.isInteger(Number(schedule.hour)) ? Math.min(23, Math.max(0, Number(schedule.hour))) : 8,
      weekday: schedule.weekday == null ? null : Math.min(6, Math.max(0, Number(schedule.weekday))),
      dayOfMonth: schedule.dayOfMonth == null ? null : Math.min(31, Math.max(1, Number(schedule.dayOfMonth))),
      recipients: cleanEmailList(schedule.recipients),
      deliveryMode: ['inline','csv','inline_csv'].includes(String(schedule.deliveryMode)) ? schedule.deliveryMode : 'inline_csv',
    },
  }
}

export async function previewReportAction(input: ReportDefinition) {
  try {
    const definition = normalizeDefinition(input)
    const { supabase } = await requireReportAdmin()
    const result = await runReport(supabase, definition)
    return { ok: true as const, rows: result.rows.slice(0, 500), fields: result.fields, columns: result.columns, totalRows: result.rows.length }
  } catch (error: any) {
    return { ok: false as const, error: error?.message || 'Report could not be generated.' }
  }
}

export async function saveReportAction(input: ReportDefinition) {
  try {
    const definition = normalizeDefinition(input)
    if (!definition.name) throw new Error('Give the report a name before saving it.')
    if (!definition.columns.length) throw new Error('Select at least one report column.')
    if (definition.schedule?.enabled) {
      if (!definition.schedule.recipients?.length) throw new Error('Add at least one email recipient before enabling a schedule.')
      if (definition.schedule.frequency === 'weekly' && definition.schedule.weekday == null) throw new Error('Choose a weekday for the weekly schedule.')
      if (definition.schedule.frequency === 'monthly' && definition.schedule.dayOfMonth == null) throw new Error('Choose a day of the month for the monthly schedule.')
    }

    const { supabase, user } = await requireReportAdmin()
    const moduleStates = await getModuleStates(supabase)
    const enabledModules = new Set(enabledModuleKeys(moduleStates))
    if (!sourceAvailableForModules(definition.dataSource, enabledModules)) {
      const missing = sourceRequiredModules(definition.dataSource).filter((module) => !enabledModules.has(module)).map(moduleLabel).join(', ')
      throw new Error(`This report cannot be saved while these modules are disabled: ${missing || 'required module'}.`)
    }
    const payload = {
      name: definition.name,
      description: definition.description || null,
      data_source: definition.dataSource,
      selected_columns: definition.columns,
      filters: definition.filters,
      sort_field: definition.sortField || null,
      sort_direction: definition.sortDirection || 'asc',
      group_field: definition.groupField || null,
      schedule_enabled: !!definition.schedule?.enabled,
      schedule_frequency: definition.schedule?.enabled ? definition.schedule.frequency || 'daily' : null,
      schedule_timezone: definition.schedule?.timezone || 'America/Chicago',
      schedule_hour: definition.schedule?.hour ?? 8,
      schedule_weekday: definition.schedule?.frequency === 'weekly' ? definition.schedule.weekday : null,
      schedule_day_of_month: definition.schedule?.frequency === 'monthly' ? definition.schedule.dayOfMonth : null,
      schedule_recipients: definition.schedule?.recipients || [],
      schedule_delivery_mode: definition.schedule?.deliveryMode || 'inline_csv',
    }

    let result
    if (definition.id) result = await supabase.from('saved_reports').update(payload).eq('id', definition.id).select('id').single()
    else result = await supabase.from('saved_reports').insert({ ...payload, owner_user_id: user.id }).select('id').single()
    if (result.error) throw result.error
    revalidatePath('/reports')
    revalidatePath(`/reports/${result.data.id}`)
    return { ok: true as const, id: result.data.id }
  } catch (error: any) {
    return { ok: false as const, error: error?.message || 'Report could not be saved.' }
  }
}

export async function deleteReportAction(reportId: string) {
  try {
    const id = cleanText(reportId, 100)
    if (!id) throw new Error('Report ID is missing.')
    const { supabase } = await requireReportAdmin()
    const { error } = await supabase.from('saved_reports').delete().eq('id', id)
    if (error) throw error
    revalidatePath('/reports')
    return { ok: true as const }
  } catch (error: any) {
    return { ok: false as const, error: error?.message || 'Report could not be deleted.' }
  }
}
