import type { Metadata } from 'next'
import Link from 'next/link'
import { PageHeader } from '@/components/page-header'
import { requireReportAdmin } from '@/lib/report-auth'
import { BUILTIN_REPORTS, sourceAvailableForModules, sourceFor } from '@/lib/report-catalog'
import { enabledModuleKeys, getModuleStates } from '@/lib/modules'
import { formatDateTime, formatHour24 } from '@/lib/format'

export const metadata: Metadata = { title: 'Reports' }

type Props = { searchParams: Promise<{ notice?: string; error?: string }> }

function scheduleLabel(report: any) {
  if (!report.schedule_enabled) return 'Manual only'
  const frequency = report.schedule_frequency === 'daily' ? 'Daily' : report.schedule_frequency === 'weekly' ? 'Weekly' : 'Monthly'
  return `${frequency} · ${formatHour24(report.schedule_hour ?? 8)}`
}

export default async function ReportsPage({ searchParams }: Props) {
  const qs = await searchParams
  const { supabase, user, isSystemAdmin } = await requireReportAdmin()
  const [{ data: saved, error }, moduleStates] = await Promise.all([
    supabase.from('saved_reports').select('id, owner_user_id, name, description, data_source, schedule_enabled, schedule_frequency, schedule_hour, schedule_timezone, schedule_recipients, last_run_at, last_run_status, updated_at').order('updated_at', { ascending:false }),
    getModuleStates(supabase),
  ])
  const enabledModules = new Set(enabledModuleKeys(moduleStates))
  const builtIns = BUILTIN_REPORTS.filter((report) => sourceAvailableForModules(report.definition.dataSource, enabledModules))

  return <>
    <PageHeader title="Reports" description="Run standard reports, combine data across enabled modules, build custom reports, and schedule recurring email delivery." action={<Link className="primary-button button-link" href="/reports/builder">Build custom report</Link>} />
    {qs.notice && <div className="banner success"><div><strong>Reports updated</strong><span>{qs.notice}</span></div></div>}
    {(qs.error || error) && <div className="banner danger"><div><strong>Reports could not be loaded</strong><span>{qs.error || error?.message}</span></div></div>}

    <section className="report-section">
      <div className="section-heading"><div><span>Standard reports</span><h2>GEAEMS report library</h2><p>These presets use the same live reporting engine as custom reports and automatically respect your access scope.</p></div></div>
      <div className="report-grid">{builtIns.map((report) => <article className="report-card" key={report.key}>
        <span>{sourceFor(report.definition.dataSource)?.label || 'Report'}</span>
        <strong>{report.name}</strong>
        <p>{report.description}</p>
        <div className="report-card-actions"><Link className="secondary-button small button-link" href={`/reports/preset/${report.key}`}>Run report</Link><Link className="text-button" href={`/reports/builder?preset=${report.key}`}>Customize</Link></div>
      </article>)}</div>
    </section>

    <section className="report-section">
      <div className="section-heading"><div><span>Saved reports</span><h2>Custom report library</h2><p>Saved reports regenerate from current data every time they run. Scheduled reports also re-check the owner's current permissions before delivery.</p></div></div>
      {(saved ?? []).length === 0 ? <div className="empty-state"><strong>No custom reports saved yet.</strong><span>Use the report builder to choose fields, filters, grouping, and optional scheduled email delivery.</span><Link className="primary-button button-link" href="/reports/builder">Build first report</Link></div> : <div className="table-card"><table><thead><tr><th>Report</th><th>Source</th><th>Schedule</th><th>Last delivery</th>{isSystemAdmin && <th>Owner</th>}<th></th></tr></thead><tbody>{(saved ?? []).map((report:any) => <tr key={report.id}>
        <td><strong>{report.name}</strong>{report.description && <div className="muted-code">{report.description}</div>}</td>
        <td>{sourceFor(report.data_source)?.label || report.data_source}{!sourceAvailableForModules(report.data_source, enabledModules) && <div className="muted-code">Required module currently disabled</div>}</td>
        <td><span className={`pill ${report.schedule_enabled ? 'green' : 'gray'}`}>{scheduleLabel(report)}</span>{report.schedule_enabled && <div className="muted-code">{(report.schedule_recipients ?? []).length} recipient{(report.schedule_recipients ?? []).length === 1 ? '' : 's'} · {report.schedule_timezone}</div>}</td>
        <td>{report.last_run_at ? <><strong>{formatDateTime(report.last_run_at)}</strong><div className="muted-code">{report.last_run_status || '—'}</div></> : 'Never'}</td>
        {isSystemAdmin && <td>{report.owner_user_id === user.id ? 'You' : 'Another administrator'}</td>}
        <td className="table-action"><Link href={`/reports/${report.id}`}>Open</Link></td>
      </tr>)}</tbody></table></div>}
    </section>
  </>
}
