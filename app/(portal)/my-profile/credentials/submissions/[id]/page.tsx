import type { Metadata } from 'next'
import Link from 'next/link'
import { notFound, redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { PageHeader } from '@/components/page-header'
import { CredentialSubmissionForm, type CredentialSubmissionType } from '@/components/credential-submission-form'
import { formatDate, titleCase } from '@/lib/format'

export const metadata: Metadata = { title: 'Credential Submission' }
type Props = { params: Promise<{ id: string }>; searchParams: Promise<{ saved?: string }> }

export default async function ProviderCredentialSubmissionPage({ params, searchParams }: Props) {
  const { id } = await params
  const { saved } = await searchParams
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')
  const { data: profile } = await supabase.from('profiles').select('provider_id').eq('id', user.id).maybeSingle()
  if (!profile?.provider_id) redirect('/auth/disabled')

  const { data: submission, error } = await supabase.from('credential_submissions')
    .select('id, provider_id, credential_type_id, credential_number, issue_date, expiration_date, provider_notes, status, submitted_at, reviewed_at, review_notes, resulting_credential_id, credential_types(id, name, category, scope_type, agency_id, requires_number, requires_issue_date, requires_expiration_date, requires_document, requires_verification, agencies(name, short_name))')
    .eq('id', id).eq('provider_id', profile.provider_id).maybeSingle()
  if (error || !submission) notFound()

  const type:any = submission.credential_types
  const [{ data: documents }, { data: currentCredential }] = await Promise.all([
    supabase.from('credential_documents').select('id, original_filename, object_path, bucket_name').or(`submission_id.eq.${id}${submission.resulting_credential_id ? `,provider_credential_id.eq.${submission.resulting_credential_id}` : ''}`).order('created_at'),
    supabase.from('provider_credentials').select('credential_number, issue_date, expiration_date').eq('provider_id', profile.provider_id).eq('credential_type_id', submission.credential_type_id).eq('is_current', true).eq('verification_status', 'verified').maybeSingle(),
  ])

  const signedDocs:any[] = []
  for (const doc of (documents ?? []) as any[]) {
    const { data } = await supabase.storage.from(doc.bucket_name || 'credential-documents').createSignedUrl(doc.object_path, 900)
    signedDocs.push({ id: doc.id, name: doc.original_filename || 'Credential document', url: data?.signedUrl || null })
  }

  const credentialType: CredentialSubmissionType = {
    id: type.id, name: type.name, category: type.category, scope_type: type.scope_type, agency_id: type.agency_id,
    agency_name: type.scope_type === 'agency' ? (type.agencies?.short_name || type.agencies?.name || 'Agency') : null,
    requires_number: !!type.requires_number, requires_issue_date: !!type.requires_issue_date,
    requires_expiration_date: !!type.requires_expiration_date, requires_document: !!type.requires_document,
    requires_verification: !!type.requires_verification,
  }
  const editable = submission.status === 'draft' || submission.status === 'changes_requested'

  return <>
    <PageHeader eyebrow="My Credentials" title={type.name} description={`Submission status: ${titleCase(submission.status)}`} action={<Link className="secondary-button button-link" href="/my-profile">Back to My Profile</Link>} />
    {saved && <div className="banner success"><div><strong>Draft saved</strong><span>You can return and submit it when you are ready.</span></div></div>}
    {submission.status === 'pending' && <div className="banner warning"><div><strong>Pending verification</strong><span>Your credential was submitted on {formatDate(submission.submitted_at?.slice(0,10))}. The current verified credential, if any, remains active until this submission is approved.</span></div></div>}
    {submission.status === 'changes_requested' && <div className="banner warning"><div><strong>Changes requested</strong><span>{submission.review_notes || 'An administrator asked you to update this submission.'}</span></div></div>}
    {submission.status === 'rejected' && <div className="banner danger"><div><strong>Submission rejected</strong><span>{submission.review_notes || 'Contact System Administration if you have questions.'}</span></div></div>}
    {submission.status === 'approved' && <div className="banner success"><div><strong>Credential approved</strong><span>This credential has been added to your verified provider record.</span></div></div>}

    {editable ? <CredentialSubmissionForm
      providerId={profile.provider_id}
      credentialTypes={[credentialType]}
      existingSubmission={submission as any}
      existingDocuments={signedDocs}
      currentCredentials={{ [credentialType.id]: currentCredential as any }}
    /> : <section className="panel">
      <div className="panel-heading"><h3>Submitted credential</h3><span>{titleCase(submission.status)}</span></div>
      <dl className="detail-list">
        <div><dt>Credential number</dt><dd>{submission.credential_number || '—'}</dd></div>
        <div><dt>Issue date</dt><dd>{formatDate(submission.issue_date)}</dd></div>
        <div><dt>Expiration date</dt><dd>{formatDate(submission.expiration_date)}</dd></div>
        <div><dt>Provider notes</dt><dd>{submission.provider_notes || '—'}</dd></div>
        <div><dt>Review notes</dt><dd>{submission.review_notes || '—'}</dd></div>
        <div><dt>Documents</dt><dd>{signedDocs.length ? signedDocs.map((doc, index) => <span key={doc.id}>{index ? ' · ' : ''}{doc.url ? <a className="text-link" href={doc.url} target="_blank" rel="noreferrer">{doc.name}</a> : doc.name}</span>) : '—'}</dd></div>
      </dl>
      {(submission.status === 'rejected' || submission.status === 'withdrawn') && <div className="form-actions"><Link className="primary-button button-link" href={`/my-profile/credentials/new?type=${submission.credential_type_id}`}>Start a new submission</Link></div>}
    </section>}
  </>
}
