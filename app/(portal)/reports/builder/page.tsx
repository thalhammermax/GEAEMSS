import type { Metadata } from 'next'
import Link from 'next/link'
import { PageHeader } from '@/components/page-header'
import { ReportBuilder } from '@/components/report-builder'
import { requireReportAdmin } from '@/lib/report-auth'
import { REPORT_SOURCES, builtInFor, sourceAvailableForModules, type ReportDefinition } from '@/lib/report-catalog'
import { reportFieldsForSource } from '@/lib/report-data'
import { enabledModuleKeys, getModuleStates } from '@/lib/modules'

export const metadata: Metadata = { title: 'Report Builder' }
type Props = { searchParams: Promise<{ id?: string; preset?: string }> }

function fromSaved(row:any): ReportDefinition {
  return {
    id: row.id, name: row.name, description: row.description || '', dataSource: row.data_source,
    columns: Array.isArray(row.selected_columns) ? row.selected_columns : [], filters: Array.isArray(row.filters) ? row.filters : [],
    sortField: row.sort_field || undefined, sortDirection: row.sort_direction || 'asc', groupField: row.group_field || undefined,
    schedule: { enabled:row.schedule_enabled, frequency:row.schedule_frequency || 'daily', timezone:row.schedule_timezone || 'America/Chicago', hour:row.schedule_hour ?? 8, weekday:row.schedule_weekday, dayOfMonth:row.schedule_day_of_month, recipients:row.schedule_recipients || [], deliveryMode:row.schedule_delivery_mode || 'inline_csv' },
  }
}

export default async function ReportBuilderPage({ searchParams }: Props) {
  const qs = await searchParams
  const { supabase } = await requireReportAdmin()
  const moduleStates = await getModuleStates(supabase)
  const enabledModules = new Set(enabledModuleKeys(moduleStates))

  let savedRow: any = null
  if (qs.id) {
    const { data } = await supabase.from('saved_reports').select('*').eq('id', qs.id).maybeSingle()
    savedRow = data
  }

  const sources = REPORT_SOURCES.filter((source) =>
    sourceAvailableForModules(source.key, enabledModules) || source.key === savedRow?.data_source
  )
  const fieldsEntries = await Promise.all(sources.map(async (source) => [
    source.key,
    await reportFieldsForSource(supabase, source.key, enabledModules),
  ] as const))
  const fieldsBySource = Object.fromEntries(fieldsEntries)

  const defaultSource = sources.find((source) => source.key === 'vehicle_operations')
    || sources.find((source) => source.key === 'fleet')
    || sources[0]

  if (!defaultSource) throw new Error('No report datasets are currently available.')

  let initial: ReportDefinition = {
    dataSource: defaultSource.key,
    columns: (fieldsBySource[defaultSource.key] || []).filter((field:any) => field.default).map((field:any) => field.key),
    filters: [],
    sortDirection: 'asc',
    schedule: { enabled:false, frequency:'daily', timezone:'America/Chicago', hour:8, weekday:1, dayOfMonth:1, recipients:[], deliveryMode:'inline_csv' },
  }
  let presetName: string | undefined

  if (savedRow) {
    initial = fromSaved(savedRow)
  } else if (qs.preset) {
    const preset = builtInFor(qs.preset)
    if (preset && sourceAvailableForModules(preset.definition.dataSource, enabledModules)) {
      const availableKeys = new Set((fieldsBySource[preset.definition.dataSource] || []).map((field:any) => field.key))
      initial = {
        ...preset.definition,
        columns: preset.definition.columns.filter((column) => availableKeys.has(column)),
        filters: preset.definition.filters.filter((filter) => availableKeys.has(filter.field)).map((filter) => ({ ...filter })),
        schedule: { enabled:false, frequency:'daily', timezone:'America/Chicago', hour:8, weekday:1, dayOfMonth:1, recipients:[], deliveryMode:'inline_csv' },
      }
      presetName = preset.name
    }
  }

  return <>
    <PageHeader eyebrow="Reports" title={initial.id ? `Edit ${initial.name}` : 'Custom Report Builder'} description="Build reports from a single module or a combined dataset such as Fleet + Inspections, then filter, group, export, save, or schedule the result." action={<Link className="secondary-button button-link" href="/reports">Back to Reports</Link>} />
    <ReportBuilder sources={sources} fieldsBySource={fieldsBySource} initial={initial} presetName={presetName} />
  </>
}
