import type { Metadata } from 'next'
import Link from 'next/link'
import { notFound } from 'next/navigation'
import { PageHeader } from '@/components/page-header'
import { ReportTable } from '@/components/report-table'
import { requireReportAdmin } from '@/lib/report-auth'
import { builtInFor, sourceFor } from '@/lib/report-catalog'
import { runReport } from '@/lib/report-data'

export const metadata: Metadata = { title:'Standard Report' }
type Props = { params:Promise<{key:string}> }

export default async function PresetReportPage({ params }:Props) {
  const { key } = await params; const preset = builtInFor(key); if (!preset) notFound()
  const { supabase } = await requireReportAdmin()
  let output:any = null; let error = ''
  try { output = await runReport(supabase,preset.definition) } catch (e:any) { error=e?.message || 'Report could not be generated.' }
  return <>
    <PageHeader eyebrow="Standard Report" title={preset.name} description={preset.description} action={<div className="header-actions"><Link className="secondary-button button-link" href="/reports">Reports</Link><Link className="secondary-button button-link" href={`/reports/builder?preset=${preset.key}`}>Customize & save</Link><Link className="primary-button button-link" href={`/reports/export?preset=${preset.key}`}>Download CSV</Link></div>} />
    {error && <div className="banner danger"><div><strong>Report could not be generated</strong><span>{error}</span></div></div>}
    <div className="summary-strip"><div><span>Data source</span><strong>{sourceFor(preset.definition.dataSource)?.label}</strong></div><div><span>Rows</span><strong>{output?.rows?.length?.toLocaleString() ?? '—'}</strong></div><div><span>Access scope</span><strong>Your current permissions</strong></div></div>
    {output && <ReportTable rows={output.rows} fields={output.fields} columns={output.columns} groupField={preset.definition.groupField} />}
  </>
}
