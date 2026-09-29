import type { Metadata } from 'next'
import Link from 'next/link'
import { PageHeader } from '@/components/page-header'
import { createClient } from '@/lib/supabase/server'
import { getCredentialAdminContext } from '@/lib/credential-access'
import { createCredentialType } from '../actions'

export const metadata: Metadata = { title: 'Add Credential Type' }
type Props = { searchParams: Promise<{ error?: string }> }

export default async function NewCredentialType({ searchParams }: Props) {
  const { error } = await searchParams
  const supabase = await createClient()
  const context = await getCredentialAdminContext(supabase)

  return <>
    <PageHeader title="Add Credential Type" description="Create either a GEAEMS System credential or an agency-owned credential. Requirements are configured separately." />
    {error && <div className="banner danger"><div><strong>Credential was not saved</strong><span>{error}</span></div></div>}
    <form action={createCredentialType} className="form-card">
      <div className="form-card-heading"><div><span>Ownership</span><h2>Who owns this credential?</h2></div></div>
      {context.isSystemAdmin ? <div className="form-grid two">
        <label className="field"><span>Credential scope *</span><select name="scope_type" defaultValue="system" required><option value="system">GEAEMS System</option><option value="agency">Agency</option></select><small>System credentials can be required across all agencies. Agency credentials remain local to their owning agency.</small></label>
        <label className="field"><span>Owning agency</span><select name="agency_id" defaultValue=""><option value="">Not applicable / System credential</option>{context.manageableAgencies.map((a:any) => <option key={a.id} value={a.id}>{a.name}</option>)}</select><small>Select an agency when Credential scope is Agency.</small></label>
      </div> : <div className="form-grid two">
        <input type="hidden" name="scope_type" value="agency" />
        <label className="field"><span>Credential scope</span><input value="Agency credential" disabled /></label>
        <label className="field"><span>Owning agency *</span><select name="agency_id" defaultValue={context.manageableAgencies.length === 1 ? context.manageableAgencies[0].id : ''} required><option value="" disabled>Select agency</option>{context.manageableAgencies.map((a:any) => <option key={a.id} value={a.id}>{a.name}</option>)}</select></label>
      </div>}

      <div className="form-section-divider"><span>Credential definition</span></div>
      <div className="form-grid three">
        <label className="field"><span>Name *</span><input name="name" required placeholder="ACLS Provider" /></label>
        <label className="field"><span>Code *</span><input name="code" required placeholder="ACLS" /><small>Used internally and in reports.</small></label>
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
