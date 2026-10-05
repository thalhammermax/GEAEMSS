import type { Metadata } from 'next'
import Link from 'next/link'
import { notFound } from 'next/navigation'
import { PageHeader } from '@/components/page-header'
import { ReportTable } from '@/components/report-table'
import { DeleteReportButton } from '@/components/delete-report-button'
import { requireReportAdmin } from '@/lib/report-auth'
import { runReport } from '@/lib/report-data'
import { sourceFor, type ReportDefinition } from '@/lib/report-catalog'
import { formatDateTime, formatHour24 } from '@/lib/format'

export const metadata: Metadata = { title:'Report' }
type Props = { params:Promise<{id:string}> }

function definitionFrom(row:any): ReportDefinition {
  return { id:row.id, name:row.name, description:row.description || '', dataSource:row.data_source, columns:Array.isArray(row.selected_columns)?row.selected_columns:[], filters:Array.isArray(row.filters)?row.filters:[], sortField:row.sort_field || undefined, sortDirection:row.sort_direction || 'asc', groupField:row.group_field || undefined }
}
function scheduleText(row:any) {
  if (!row.schedule_enabled) return 'Not scheduled'
  const display = formatHour24(row.schedule_hour ?? 8)
  if (row.schedule_frequency === 'weekly') return `Weekly on ${['Sunday','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday'][row.schedule_weekday ?? 0]} at ${display}`
  if (row.schedule_frequency === 'monthly') return `Monthly on day ${row.schedule_day_of_month} at ${display}`
  return `Daily at ${display}`
}

export default async function SavedReportPage({ params }:Props) {
  const { id } = await params
  const { supabase } = await requireReportAdmin()
  const [{ data:report }, { data:runs }] = await Promise.all([
    supabase.from('saved_reports').select('*').eq('id',id).maybeSingle(),
    supabase.from('report_schedule_runs').select('id, created_at, scheduled_local_date, status, recipient_count, row_count, error_message').eq('saved_report_id',id).order('created_at',{ascending:false}).limit(10),
  ])
  if (!report) notFound()
  const definition = definitionFrom(report)
  let output:any = null; let error = ''
  try { output = await runReport(supabase, definition) } catch (e:any) { error = e?.message || 'Report could not be generated.' }
  const source = sourceFor(report.data_source)

  return <>
    <PageHeader eyebrow="Saved Report" title={report.name} description={report.description || source?.description || 'Custom GEAEMS report.'} action={<div className="header-actions"><Link className="secondary-button button-link" href="/reports">Reports</Link><Link className="secondary-button button-link" href={`/reports/builder?id=${report.id}`}>Edit</Link><Link className="primary-button button-link" href={`/reports/export?id=${report.id}`}>Download CSV</Link></div>} />
    {error && <div className="banner danger"><div><strong>Report could not be generated</strong><span>{error}</span></div></div>}
    <div className="summary-strip report-summary-strip">
      <div><span>Data source</span><strong>{source?.label || report.data_source}</strong></div>
      <div><span>Rows</span><strong>{output?.rows?.length?.toLocaleString() ?? '—'}</strong></div>
      <div><span>Schedule</span><strong>{scheduleText(report)}</strong></div>
      <div><span>Last delivery</span><strong>{report.last_run_at ? formatDateTime(report.last_run_at) : 'Never'}</strong></div>
    </div>

    {output && <ReportTable rows={output.rows} fields={output.fields} columns={output.columns} groupField={definition.groupField} />}

    <div className="dashboard-columns report-detail-columns">
      <section className="panel"><div className="panel-heading"><div><span>Email delivery</span><h2>Schedule</h2></div><Link className="text-button" href={`/reports/builder?id=${report.id}`}>Edit schedule</Link></div>
        {!report.schedule_enabled ? <div className="empty-inline">This report runs manually only.</div> : <dl className="detail-list"><div><dt>Frequency</dt><dd>{scheduleText(report)}</dd></div><div><dt>Time zone</dt><dd>{report.schedule_timezone}</dd></div><div><dt>Recipients</dt><dd>{(report.schedule_recipients ?? []).join(', ') || '—'}</dd></div><div><dt>Delivery format</dt><dd>{report.schedule_delivery_mode === 'inline_csv' ? 'Table + CSV attachment' : report.schedule_delivery_mode === 'csv' ? 'CSV attachment' : 'Table in email'}</dd></div></dl>}
      </section>
      <section className="panel"><div className="panel-heading"><div><span>Delivery history</span><h2>Recent scheduled runs</h2></div></div>
        {(runs ?? []).length === 0 ? <div className="empty-inline">No scheduled deliveries yet.</div> : <div className="mini-log">{(runs ?? []).map((run:any) => <div key={run.id}><div><strong>{formatDateTime(run.created_at)}</strong><span>{run.row_count} rows · {run.recipient_count} recipients</span></div><span className={`pill ${run.status==='sent'?'green':run.status==='failed'?'red':'gray'}`}>{run.status}</span>{run.error_message && <small>{run.error_message}</small>}</div>)}</div>}
      </section>
    </div>
    <div className="danger-zone"><div><strong>Delete saved report</strong><span>This removes the saved definition, schedule, and delivery history. It does not delete any underlying system data.</span></div><DeleteReportButton reportId={report.id} /></div>
  </>
}
