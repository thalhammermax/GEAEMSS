import type { Metadata } from 'next'
import Link from 'next/link'
import { PageHeader } from '@/components/page-header'
import { requireCEManagerPage } from '@/lib/ce-auth'
import { reviewExternalCE } from '../../actions'

export const metadata: Metadata = { title: 'External CE Review' }
type Props = { searchParams: Promise<{ notice?: string; error?: string; status?: string }> }

export default async function ExternalCEReviewPage({ searchParams }: Props) {
  const qs = await searchParams
  const status = ['pending','approved','rejected','all'].includes(qs.status || '') ? (qs.status || 'pending') : 'pending'
  const { supabase } = await requireCEManagerPage()
  const { data: rows, error } = await supabase.rpc('ce_external_review_queue', { p_status: status })

  const withUrls = await Promise.all((rows ?? []).map(async (row:any) => {
    if (!row.certificate_path) return { ...row, certificateUrl: null }
    const { data } = await supabase.storage.from('ce-certificates').createSignedUrl(row.certificate_path, 3600)
    return { ...row, certificateUrl: data?.signedUrl || null }
  }))

  return <>
    <PageHeader eyebrow="CE Administration" title="External CE Review" description="Approve or reject provider-uploaded online and outside-course completion certificates." action={<Link className="secondary-button button-link" href="/ce">Back to CE</Link>} />
    {qs.notice && <div className="banner success"><div><strong>Review saved</strong><span>{qs.notice}</span></div></div>}
    {qs.error && <div className="banner danger"><div><strong>Review failed</strong><span>{qs.error}</span></div></div>}
    <form className="filter-bar" method="get"><div className="results-meta"><strong>{withUrls.length}</strong> visible submission{withUrls.length === 1 ? '' : 's'}</div><select name="status" defaultValue={status}><option value="pending">Pending review</option><option value="approved">Approved</option><option value="rejected">Rejected</option><option value="all">All submissions</option></select><button className="secondary-button" type="submit">Apply</button></form>

    {error ? <div className="empty-state danger-text"><strong>Unable to load external CE</strong><span>{error.message}</span></div> : withUrls.length === 0 ? <div className="empty-state"><strong>No submissions in this view</strong><span>Provider-uploaded CE certificates will appear here.</span></div> : <div className="review-card-list">{withUrls.map((row:any) => <section className="form-card compact-card" key={row.id}>
      <div className="form-card-heading"><div><span>{row.provider_name}{row.provider_number ? ` · ${row.provider_number}` : ''}</span><h2>{row.title}</h2></div><span className={`pill ${row.status === 'approved' ? 'green' : row.status === 'rejected' ? 'red' : 'amber'}`}>{row.status}</span></div>
      <dl className="detail-list"><div><dt>Completed</dt><dd>{row.completion_date}</dd></div><div><dt>CE hours</dt><dd>{Number(row.credit_hours || 0).toFixed(2)}</dd></div><div><dt>Sponsor</dt><dd>{row.sponsor || '—'}</dd></div><div><dt>Category</dt><dd>{row.category || '—'}</dd></div><div><dt>Provider note</dt><dd>{row.notes || '—'}</dd></div><div><dt>Certificate</dt><dd>{row.certificateUrl ? <a className="text-link" href={row.certificateUrl} target="_blank" rel="noreferrer">Open {row.certificate_filename || 'certificate'}</a> : 'Not available'}</dd></div></dl>
      {row.status === 'pending' ? <form action={reviewExternalCE}><input type="hidden" name="submission_id" value={row.id}/><label className="field"><span>Coordinator review note</span><textarea name="review_notes" rows={3} placeholder="Optional for approval; recommended for rejection."/></label><div className="form-actions split-actions"><button className="secondary-button danger-outline" type="submit" name="decision" value="rejected">Reject</button><button className="primary-button" type="submit" name="decision" value="approved">Approve & add to transcript</button></div></form> : <div className="banner"><div><strong>Reviewed</strong><span>{row.review_notes || 'No review note.'}</span></div></div>}
    </section>)}</div>}
  </>
}
