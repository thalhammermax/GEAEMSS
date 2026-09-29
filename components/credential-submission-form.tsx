'use client'

import { useMemo, useState } from 'react'
import { useRouter } from 'next/navigation'
import { createClient } from '@/lib/supabase/client'

export type CredentialSubmissionType = {
  id: string
  name: string
  category: string
  scope_type: 'system' | 'agency'
  agency_id?: string | null
  agency_name?: string | null
  requires_number: boolean
  requires_issue_date: boolean
  requires_expiration_date: boolean
  requires_document: boolean
  requires_verification: boolean
}

type Submission = {
  id: string
  credential_type_id: string
  credential_number?: string | null
  issue_date?: string | null
  expiration_date?: string | null
  provider_notes?: string | null
  status: string
}

type ExistingDocument = {
  id: string
  name: string
  url?: string | null
}

type CurrentCredential = {
  credential_number?: string | null
  issue_date?: string | null
  expiration_date?: string | null
} | null

function safeFilename(name: string) {
  const cleaned = name.replace(/[^a-zA-Z0-9._-]+/g, '-').replace(/-+/g, '-').replace(/^-|-$/g, '')
  return cleaned || 'credential-document'
}

export function CredentialSubmissionForm({
  providerId,
  credentialTypes,
  preselectedTypeId,
  existingSubmission,
  existingDocuments = [],
  currentCredentials = {},
}: {
  providerId: string
  credentialTypes: CredentialSubmissionType[]
  preselectedTypeId?: string | null
  existingSubmission?: Submission | null
  existingDocuments?: ExistingDocument[]
  currentCredentials?: Record<string, CurrentCredential>
}) {
  const router = useRouter()
  const supabase = useMemo(() => createClient(), [])
  const [typeId, setTypeId] = useState(existingSubmission?.credential_type_id || preselectedTypeId || credentialTypes[0]?.id || '')
  const [credentialNumber, setCredentialNumber] = useState(existingSubmission?.credential_number || '')
  const [issueDate, setIssueDate] = useState(existingSubmission?.issue_date || '')
  const [expirationDate, setExpirationDate] = useState(existingSubmission?.expiration_date || '')
  const [providerNotes, setProviderNotes] = useState(existingSubmission?.provider_notes || '')
  const [file, setFile] = useState<File | null>(null)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const selected = credentialTypes.find((type) => type.id === typeId)
  const current = currentCredentials[typeId] || null
  const editable = !existingSubmission || existingSubmission.status === 'draft' || existingSubmission.status === 'changes_requested'

  async function save(finalize: boolean) {
    if (!selected) return
    setBusy(true)
    setError(null)

    try {
      if (selected.requires_number && !credentialNumber.trim() && finalize) throw new Error('Credential number is required.')
      if (selected.requires_issue_date && !issueDate && finalize) throw new Error('Issue date is required.')
      if (selected.requires_expiration_date && !expirationDate && finalize) throw new Error('Expiration date is required.')
      if (issueDate && expirationDate && expirationDate < issueDate) throw new Error('Expiration date cannot be before the issue date.')
      if (selected.requires_document && existingDocuments.length === 0 && !file && finalize) throw new Error('A supporting credential document is required.')
      if (file && file.size > 10 * 1024 * 1024) throw new Error('Credential documents must be 10 MB or smaller.')
      if (file && !['application/pdf', 'image/jpeg', 'image/png', 'image/webp'].includes(file.type)) throw new Error('Upload a PDF, JPG, PNG, or WebP credential document.')

      let submissionId = existingSubmission?.id || null
      const values = {
        provider_id: providerId,
        credential_type_id: selected.id,
        credential_number: credentialNumber.trim() || null,
        issue_date: issueDate || null,
        expiration_date: expirationDate || null,
        provider_notes: providerNotes.trim() || null,
      }

      if (submissionId) {
        const { error: updateError } = await supabase.from('credential_submissions').update(values).eq('id', submissionId)
        if (updateError) throw updateError
      } else {
        const { data, error: insertError } = await supabase.from('credential_submissions').insert({ ...values, status: 'draft' }).select('id').single()
        if (insertError) throw insertError
        submissionId = data.id
      }

      if (!submissionId) throw new Error('Unable to create the credential submission.')

      if (file) {
        const objectPath = `${providerId}/${submissionId}/${crypto.randomUUID()}-${safeFilename(file.name)}`
        const { error: uploadError } = await supabase.storage.from('credential-documents').upload(objectPath, file, {
          upsert: false,
          contentType: file.type,
          cacheControl: '3600',
        })
        if (uploadError) throw uploadError

        const { error: metadataError } = await supabase.from('credential_documents').insert({
          submission_id: submissionId,
          bucket_name: 'credential-documents',
          object_path: objectPath,
          original_filename: file.name,
          mime_type: file.type,
          size_bytes: file.size,
        })
        if (metadataError) {
          await supabase.storage.from('credential-documents').remove([objectPath])
          throw metadataError
        }
      }

      if (!finalize) {
        router.push(`/my-profile/credentials/submissions/${submissionId}?saved=1`)
        router.refresh()
        return
      }

      const { data: result, error: finalizeError } = await supabase.rpc('finalize_credential_submission', { p_submission_id: submissionId })
      if (finalizeError) throw finalizeError

      const message = result === 'approved'
        ? 'Credential saved and accepted.'
        : 'Credential submitted for verification.'
      router.push(`/my-profile?credentialNotice=${encodeURIComponent(message)}`)
      router.refresh()
    } catch (err: any) {
      setError(err?.message || 'Credential submission could not be saved.')
    } finally {
      setBusy(false)
    }
  }

  if (!selected) {
    return <div className="empty-state compact"><strong>No credential types are available</strong><span>Your System Administrator may need to configure credential definitions or agency affiliations.</span></div>
  }

  return <div className="form-card">
    <div className="form-card-heading"><div><span>Provider self-service</span><h2>{existingSubmission ? 'Update credential submission' : 'Add or renew a credential'}</h2></div><span className={`pill ${selected.requires_verification ? 'amber' : 'green'}`}>{selected.requires_verification ? 'Verification required' : 'Self-attested'}</span></div>

    {error && <div className="banner danger"><div><strong>Credential was not saved</strong><span>{error}</span></div></div>}

    <div className="form-grid">
      <label className="field span-two"><span>Credential *</span><select value={typeId} onChange={(e) => setTypeId(e.target.value)} disabled={!!existingSubmission || busy}>
        {credentialTypes.map((type) => <option key={type.id} value={type.id}>{type.name}{type.scope_type === 'agency' ? ` — ${type.agency_name || 'Agency'}` : ' — GEAEMS System'}</option>)}
      </select><small>{selected.category} · {selected.scope_type === 'agency' ? selected.agency_name || 'Agency credential' : 'GEAEMS System credential'}</small></label>

      {current && <div className="notes-box"><span>Current verified credential</span><p>{current.credential_number ? `#${current.credential_number} · ` : ''}{current.expiration_date ? `Expires ${current.expiration_date}` : 'No expiration date'}.</p></div>}

      {(selected.requires_number || credentialNumber) && <label className="field"><span>Credential number {selected.requires_number ? '*' : ''}</span><input value={credentialNumber} onChange={(e) => setCredentialNumber(e.target.value)} disabled={!editable || busy}/></label>}
      {(selected.requires_issue_date || issueDate || true) && <label className="field"><span>Issue date {selected.requires_issue_date ? '*' : ''}</span><input type="date" value={issueDate} onChange={(e) => setIssueDate(e.target.value)} disabled={!editable || busy}/></label>}
      {(selected.requires_expiration_date || expirationDate || true) && <label className="field"><span>Expiration date {selected.requires_expiration_date ? '*' : ''}</span><input type="date" value={expirationDate} onChange={(e) => setExpirationDate(e.target.value)} disabled={!editable || busy}/></label>}

      <label className="field span-two"><span>Supporting document {selected.requires_document ? '*' : ''}</span><input type="file" accept="application/pdf,image/jpeg,image/png,image/webp" onChange={(e) => setFile(e.target.files?.[0] || null)} disabled={!editable || busy}/><small>PDF, JPG, PNG, or WebP. Maximum 10 MB.</small></label>

      {existingDocuments.length > 0 && <div className="notes-box"><span>Documents already attached</span><p>{existingDocuments.map((doc, index) => <span key={doc.id}>{index > 0 ? ' · ' : ''}{doc.url ? <a className="text-link" href={doc.url} target="_blank" rel="noreferrer">{doc.name}</a> : doc.name}</span>)}</p></div>}

      <label className="field span-two"><span>Provider notes</span><textarea value={providerNotes} onChange={(e) => setProviderNotes(e.target.value)} disabled={!editable || busy} placeholder="Optional context for the reviewing administrator"/></label>
    </div>

    {editable && <div className="form-actions"><button className="secondary-button" type="button" disabled={busy} onClick={() => save(false)}>{busy ? 'Saving…' : 'Save draft'}</button><button className="primary-button" type="button" disabled={busy} onClick={() => save(true)}>{busy ? 'Submitting…' : selected.requires_verification ? 'Submit for verification' : 'Save credential'}</button></div>}
  </div>
}
