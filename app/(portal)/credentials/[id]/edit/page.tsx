import type { Metadata } from 'next'
import Link from 'next/link'
import { notFound } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { PageHeader } from '@/components/page-header'
import { deleteCredentialType, updateCredentialType } from '../../actions'

export const metadata: Metadata = { title: 'Edit Credential Type' }
type Props = { params: Promise<{ id: string }>; searchParams: Promise<{ error?: string; saved?: string }> }

export default async function EditCredentialType({ params, searchParams }: Props) {
  const { id } = await params
  const { error, saved } = await searchParams
  const supabase = await createClient()
  const { data: credential } = await supabase.from('credential_types').select('*').eq('id', id).maybeSingle()
  if (!credential) notFound()
  const [{ count: recordCount }, { count: requirementCount }] = await Promise.all([
    supabase.from('provider_credentials').select('*', { count: 'exact', head: true }).eq('credential_type_id', id),
    supabase.from('credential_requirements').select('*', { count: 'exact', head: true }).eq('credential_type_id', id),
  ])

  return <>
    <PageHeader title={credential.name} description="Edit the credential definition. Historical provider credential records are preserved when a credential is deactivated." />
    {saved && <div className="banner success"><div><strong>Credential saved</strong><span>Your changes are active.</span></div></div>}
    {error && <div className="banner danger"><div><strong>Credential was not saved</strong><span>{error}</span></div></div>}
    <form action={updateCredentialType} className="form-card">
      <input type="hidden" name="id" value={id} />
      <div className="form-card-heading"><div><span>Credential definition</span><h2>Identity and renewal rules</h2></div><span className={`pill ${credential.active ? 'green' : ''}`}>{credential.active ? 'Active' : 'Inactive'}</span></div>
      <div className="form-grid three">
        <label className="field"><span>Name *</span><input name="name" required defaultValue={credential.name} /></label>
        <label className="field"><span>Code *</span><input name="code" required defaultValue={credential.code} /></label>
        <label className="field"><span>Category *</span><input name="category" required defaultValue={credential.category} /></label>
        <label className="field"><span>Renewal cycle (months)</span><input name="renewal_months" type="number" min="1" step="1" defaultValue={credential.renewal_months ?? ''} /></label>
        <label className="field span-two"><span>Warning days</span><input name="warning_days" defaultValue={(credential.warning_days ?? []).join(', ')} /></label>
        <label className="field span-full"><span>Description</span><textarea name="description" rows={3} defaultValue={credential.description ?? ''} /></label>
      </div>
      <div className="form-section-divider"><span>Required information</span></div>
      <div className="inline-options">
        <label className="checkbox-row"><input type="checkbox" name="requires_number" defaultChecked={credential.requires_number} />Credential number</label>
        <label className="checkbox-row"><input type="checkbox" name="requires_issue_date" defaultChecked={credential.requires_issue_date} />Issue date</label>
        <label className="checkbox-row"><input type="checkbox" name="requires_expiration_date" defaultChecked={credential.requires_expiration_date} />Expiration date</label>
        <label className="checkbox-row"><input type="checkbox" name="requires_document" defaultChecked={credential.requires_document} />Supporting document</label>
        <label className="checkbox-row"><input type="checkbox" name="requires_verification" defaultChecked={credential.requires_verification} />Administrator verification</label>
        <label className="checkbox-row"><input type="checkbox" name="active" defaultChecked={credential.active} />Active</label>
      </div>
      <div className="form-actions"><Link className="secondary-button button-link" href="/credentials">Back</Link><button className="primary-button" type="submit">Save changes</button></div>
    </form>
    <section className="form-card compact-card danger-zone">
      <div className="form-card-heading"><div><span>Permanent deletion</span><h2>Delete credential type</h2></div></div>
      <p className="panel-copy">This credential currently has <strong>{recordCount ?? 0}</strong> provider record(s) and <strong>{requirementCount ?? 0}</strong> requirement(s). If it is referenced anywhere, the portal will deactivate it instead of destroying history.</p>
      <form action={deleteCredentialType}><input type="hidden" name="id" value={id} /><button className="secondary-button danger-outline" type="submit">Delete credential type</button></form>
    </section>
  </>
}
