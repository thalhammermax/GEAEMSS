import type { Metadata } from 'next'
import Link from 'next/link'
import { notFound } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { PageHeader } from '@/components/page-header'
import { formatQuantity, relationOne } from '@/lib/narcotics'

export const metadata: Metadata = { title: 'Narcotics Count' }
type Props = { params: Promise<{ id: string }>; searchParams: Promise<{ submitted?: string }> }

export default async function NarcoticsCountDetail({ params, searchParams }: Props) {
  const { id } = await params
  const qs = await searchParams
  const supabase = await createClient()
  const { data: count } = await supabase.from('narcotics_counts').select('*, vehicles(unit_number, fleet_number, agencies(name, short_name)), narcotics_count_templates(name)').eq('id', id).maybeSingle()
  if (!count) notFound()
  const { data: lines } = await supabase.from('narcotics_count_lines').select('*').eq('count_id', id).order('sort_order').order('medication_name')
  const vehicle = relationOne<any>(count.vehicles)
  const agency = relationOne<any>(vehicle?.agencies)
  const template = relationOne<any>(count.narcotics_count_templates)
  return <>
    <PageHeader eyebrow="Narcotics Count" title={vehicle?.unit_number || vehicle?.fleet_number || 'Apparatus'} description={`${agency?.name || 'Agency'} · ${count.count_date}`} action={<Link className="secondary-button button-link" href="/narcotics">Back to Narcotics</Link>} />
    {qs.submitted && <div className="banner success"><div><strong>Daily count submitted</strong><span>The signed record is now locked from editing.</span></div></div>}
    <div className="summary-strip"><div><span>Status</span><strong>{count.status === 'submitted' ? 'Signed' : count.status}</strong></div><div><span>Form</span><strong style={{fontSize:16}}>{template?.name || '—'}</strong></div><div><span>Seal Number</span><strong style={{fontSize:16}}>{count.seal_number || '—'}</strong></div><div><span>Discrepancy</span><strong>{count.has_discrepancy ? 'Yes' : 'No'}</strong></div><div><span>Signed by</span><strong style={{fontSize:16}}>{count.signed_name || '—'}</strong></div></div>
    <div className="table-card"><table><thead><tr><th>Controlled substance</th><th>Expected</th><th>Actual</th><th>Status</th><th>Notes</th></tr></thead><tbody>{(lines ?? []).map((line:any) => <tr key={line.id}><td><strong>{line.medication_name}</strong>{line.concentration && <div className="muted-code">{line.concentration}</div>}</td><td>{formatQuantity(line.expected_quantity)} {line.unit_label}</td><td>{formatQuantity(line.actual_quantity)} {line.unit_label}</td><td><span className={`pill ${line.discrepancy ? 'red' : 'green'}`}>{line.discrepancy ? 'Discrepancy' : 'Matched'}</span></td><td>{line.notes || '—'}</td></tr>)}</tbody></table></div>
    {count.prior_seal_number && count.seal_number !== count.prior_seal_number && <section className="panel"><div className="panel-heading"><h3>Seal change</h3><span>Documented at submission</span></div><dl className="detail-list"><div><dt>Previous seal</dt><dd>{count.prior_seal_number}</dd></div><div><dt>New seal</dt><dd>{count.seal_number}</dd></div><div><dt>Reason</dt><dd>{count.seal_change_reason || '—'}</dd></div></dl></section>}
    {count.status === 'submitted' && <section className="panel signature-record"><div className="panel-heading"><h3>Electronic signature record</h3><span>Immutable submission metadata</span></div><dl className="detail-list"><div><dt>Signed name</dt><dd>{count.signed_name}</dd></div><div><dt>Signed at</dt><dd>{count.signed_at ? new Date(count.signed_at).toLocaleString() : '—'}</dd></div><div><dt>Attestation</dt><dd>{count.signature_attestation}</dd></div><div><dt>Signature hash</dt><dd><code>{count.signature_hash}</code></dd></div></dl></section>}
  </>
}
