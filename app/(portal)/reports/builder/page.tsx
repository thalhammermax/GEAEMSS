import type { Metadata } from 'next'
import Link from 'next/link'
import { PageHeader } from '@/components/page-header'
import { ReportBuilder } from '@/components/report-builder'
import { requireReportAdmin } from '@/lib/report-auth'
import { BUILTIN_REPORTS, REPORT_SOURCES, builtInFor, type ReportDefinition } from '@/lib/report-catalog'
import { reportFieldsForSource } from '@/lib/report-data'

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
  const fieldsEntries = await Promise.all(REPORT_SOURCES.map(async (source) => [source.key, await reportFieldsForSource(supabase, source.key)] as const))
  const fieldsBySource = Object.fromEntries(fieldsEntries)
  let initial: ReportDefinition = { dataSource:'personnel', columns:fieldsBySource.personnel.filter((f:any) => f.default).map((f:any) => f.key), filters:[], sortDirection:'asc', schedule:{ enabled:false, frequency:'daily', timezone:'America/Chicago', hour:8, weekday:1, dayOfMonth:1, recipients:[], deliveryMode:'inline_csv' } }
  let presetName: string | undefined

  if (qs.id) {
    const { data } = await supabase.from('saved_reports').select('*').eq('id', qs.id).maybeSingle()
    if (data) initial = fromSaved(data)
  } else if (qs.preset) {
    const preset = builtInFor(qs.preset)
    if (preset) { initial = { ...preset.definition, columns:[...preset.definition.columns], filters:preset.definition.filters.map((f) => ({ ...f })), schedule:{ enabled:false, frequency:'daily', timezone:'America/Chicago', hour:8, weekday:1, dayOfMonth:1, recipients:[], deliveryMode:'inline_csv' } }; presetName = preset.name }
  }

  return <>
    <PageHeader eyebrow="Reports" title={initial.id ? `Edit ${initial.name}` : 'Custom Report Builder'} description="Choose a data source, fields, filters, grouping, and optional scheduled email delivery." action={<Link className="secondary-button button-link" href="/reports">Back to Reports</Link>} />
    <ReportBuilder sources={REPORT_SOURCES} fieldsBySource={fieldsBySource} initial={initial} presetName={presetName} />
  </>
}
