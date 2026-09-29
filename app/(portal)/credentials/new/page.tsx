import type { Metadata } from 'next'
import Link from 'next/link'
import { PageHeader } from '@/components/page-header'
import { createCredentialType } from '../actions'

export const metadata: Metadata = { title: 'Add Credential Type' }
type Props = { searchParams: Promise<{ error?: string }> }

export default async function NewCredentialType({ searchParams }: Props) {
  const { error } = await searchParams
  return <>
    <PageHeader title="Add Credential Type" description="Create a credential definition. Requirements are configured separately so the same credential can apply to different provider groups." />
    {error && <div className="banner danger"><div><strong>Credential was not saved</strong><span>{error}</span></div></div>}
    <form action={createCredentialType} className="form-card">
      <div className="form-card-heading"><div><span>Credential definition</span><h2>Identity and renewal rules</h2></div></div>
      <div className="form-grid three">
        <label className="field"><span>Name *</span><input name="name" required placeholder="ACLS Provider" /></label>
        <label className="field"><span>Code *</span><input name="code" required placeholder="ACLS" /><small>Used internally and in reports. Letters, numbers, dashes and underscores are safest.</small></label>
        <label className="field"><span>Category *</span><input name="category" required defaultValue="Certification" placeholder="Certification" /></label>
        <label className="field"><span>Renewal cycle (months)</span><input name="renewal_months" type="number" min="1" step="1" placeholder="24" /><small>Leave blank for variable or nonstandard renewal periods.</small></label>
        <label className="field span-two"><span>Warning days</span><input name="warning_days" defaultValue="120, 90, 60, 30, 14, 7, 1" /><small>Comma-separated days before expiration used by the alert engine.</small></label>
        <label className="field span-full"><span>Description</span><textarea name="description" rows={3} /></label>
      </div>
      <div className="form-section-divider"><span>Required information</span></div>
      <div className="inline-options">
        <label className="checkbox-row"><input type="checkbox" name="requires_number" />Credential number</label>
        <label className="checkbox-row"><input type="checkbox" name="requires_issue_date" />Issue date</label>
        <label className="checkbox-row"><input type="checkbox" name="requires_expiration_date" defaultChecked />Expiration date</label>
        <label className="checkbox-row"><input type="checkbox" name="requires_document" />Supporting document</label>
        <label className="checkbox-row"><input type="checkbox" name="requires_verification" defaultChecked />Administrator verification</label>
        <label className="checkbox-row"><input type="checkbox" name="active" defaultChecked />Active</label>
      </div>
      <div className="form-actions"><Link className="secondary-button button-link" href="/credentials">Cancel</Link><button className="primary-button" type="submit">Create credential</button></div>
    </form>
  </>
}
