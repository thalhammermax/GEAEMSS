import type { Metadata } from 'next'
import Link from 'next/link'
import { notFound } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { PageHeader } from '@/components/page-header'
import { formatDate, titleCase } from '@/lib/format'
import { approveCredentialSubmission, rejectCredentialSubmission, requestCredentialChanges } from '../actions'

export const metadata: Metadata = { title: 'Review Credential' }
type Props = { params: Promise<{ id: string }>; searchParams: Promise<{ error?: string }> }

export default async function ReviewCredentialSubmissionPage({ params, searchParams }: Props) {
  const { id } = await params
  const { error: queryError } = await searchParams
  const supabase = await createClient()
  const { data: submission, error } = await supabase.from('credential_submissions').select('id, provider_id, credential_type_id, credential_number, issue_date, expiration_date, provider_notes, status, submitted_at, reviewed_at, review_notes, resulting_credential_id, providers(id, first_name, last_name, provider_number, email), credential_types(id, name, category, scope_type, requires_number, requires_issue_date, requires_expiration_date, requires_document, requires_verification, agencies(name, short_name))').eq('id', id).maybeSingle()
  if (error || !submission) notFound()

  const [{ data: current }, { data: documents }] = await Promise.all([
    supabase.from('provider_credentials').select('id, credential_number, issue_date, expiration_date, verified_at').eq('provider_id', submission.provider_id).eq('credential_type_id', submission.credential_type_id).eq('is_current', true).eq('verification_status', 'verified').maybeSingle(),
    supabase.from('credential_documents').select('id, original_filename, object_path, bucket_name, mime_type, size_bytes').or(`submission_id.eq.${id}${submission.resulting_credential_id ? `,provider_credential_id.eq.${submission.resulting_credential_id}` : ''}`).order('created_at'),
  ])

  const signedDocs:any[] = []
  for (const doc of (documents ?? []) as any[]) {
    const { data } = await supabase.storage.from(doc.bucket_name || 'credential-documents').createSignedUrl(doc.object_path, 900)
    signedDocs.push({ ...doc, url: data?.signedUrl || null })
  }
  const provider:any = submission.providers
  const type:any = submission.credential_types
  const reviewable = submission.status === 'pending' || submission.status === 'changes_requested'

  return <>
    <PageHeader eyebrow="Credential Verification" title={type.name} description={`${provider.first_name} ${provider.last_name} · ${titleCase(submission.status)}`} action={<Link className="secondary-button button-link" href="/credentials/submissions">Back to queue</Link>} />
    {queryError && <div className="banner danger"><div><strong>Credential action failed</strong><span>{queryError}</span></div></div>}

    <div className="profile-grid">
      <section className="panel"><div className="panel-heading"><h3>Provider submission</h3><span>{type.scope_type === 'agency' ? (type.agencies?.short_name || type.agencies?.name || 'Agency credential') : 'GEAEMS System'}</span></div><dl className="detail-list">
        <div><dt>Provider</dt><dd><Link className="text-link" href={`/personnel/${provider.id}`}>{provider.first_name} {provider.last_name}</Link> · {provider.provider_number || 'No System ID'}</dd></div>
        <div><dt>Credential number</dt><dd>{submission.credential_number || '—'}</dd></div><div><dt>Issue date</dt><dd>{formatDate(submission.issue_date)}</dd></div><div><dt>Expiration date</dt><dd>{formatDate(submission.expiration_date)}</dd></div>
        <div><dt>Provider notes</dt><dd>{submission.provider_notes || '—'}</dd></div><div><dt>Submitted</dt><dd>{formatDate(submission.submitted_at?.slice(0,10))}</dd></div>
        <div><dt>Documents</dt><dd>{signedDocs.length ? signedDocs.map((doc,index) => <span key={doc.id}>{index ? ' · ' : ''}{doc.url ? <a className="text-link" href={doc.url} target="_blank" rel="noreferrer">{doc.original_filename || 'Document'}</a> : doc.original_filename || 'Document'}</span>) : <span className={type.requires_document ? 'danger-text' : ''}>{type.requires_document ? 'Required document missing' : 'None'}</span>}</dd></div>
      </dl></section>

      <section className="panel"><div className="panel-heading"><h3>Current verified credential</h3><span>{current ? 'Existing record remains active' : 'No current record'}</span></div>{current ? <dl className="detail-list"><div><dt>Credential number</dt><dd>{current.credential_number || '—'}</dd></div><div><dt>Issue date</dt><dd>{formatDate(current.issue_date)}</dd></div><div><dt>Expiration date</dt><dd>{formatDate(current.expiration_date)}</dd></div></dl> : <div className="empty-state compact"><strong>No verified credential</strong><span>Approval will create the provider's first current record for this credential type.</span></div>}</section>
    </div>

    {submission.review_notes && !reviewable && <div className={`banner ${submission.status === 'rejected' ? 'danger' : 'success'}`}><div><strong>Review notes</strong><span>{submission.review_notes}</span></div></div>}

    {reviewable && <section className="form-card"><div className="form-card-heading"><div><span>Administrative review</span><h2>Verify this credential</h2></div></div><form><label className="field"><span>Review notes</span><textarea name="review_notes" placeholder="Optional for approval; required when requesting changes or rejecting" /></label><input type="hidden" name="id" value={submission.id}/><div className="form-actions"><button className="secondary-button" formAction={requestCredentialChanges}>Request changes</button><button className="secondary-button danger-outline" formAction={rejectCredentialSubmission}>Reject</button><button className="primary-button" formAction={approveCredentialSubmission}>Approve credential</button></div></form></section>}
  </>
}
