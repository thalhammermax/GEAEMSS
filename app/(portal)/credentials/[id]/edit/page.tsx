import type { Metadata } from 'next'
import Link from 'next/link'
import { notFound } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { getCredentialAdminContext } from '@/lib/credential-access'
import { PageHeader } from '@/components/page-header'
import { createCredentialRequirement, deleteCredentialRequirement, deleteCredentialType, updateCredentialType } from '../../actions'

export const metadata: Metadata = { title: 'Credential' }
type Props = { params: Promise<{ id: string }>; searchParams: Promise<{ error?: string; saved?: string; notice?: string }> }

function canManageAgency(agencies: any[], agencyId: string | null) {
  return !!agencyId && agencies.some((a:any) => a.id === agencyId)
}

export default async function EditCredentialType({ params, searchParams }: Props) {
  const { id } = await params
  const { error, saved, notice } = await searchParams
  const supabase = await createClient()
  const context = await getCredentialAdminContext(supabase)

  const [{ data: credential }, { data: levels }, { data: requirements }] = await Promise.all([
    supabase.from('credential_types').select('*, agencies(name, short_name)').eq('id', id).maybeSingle(),
    supabase.from('provider_levels').select('id, name, code').eq('active', true).order('sort_order'),
    supabase.from('credential_requirements').select('id, scope_type, agency_id, provider_level_id, required, effective_start_date, effective_end_date, notes, agencies(name, short_name), provider_levels(name, code)').eq('credential_type_id', id).order('scope_type').order('created_at'),
  ])
  if (!credential) notFound()

  const canEditDefinition = context.isSystemAdmin || (
    credential.scope_type === 'agency' && canManageAgency(context.manageableAgencies, credential.agency_id)
  )

  const [{ count: recordCount }, { count: submissionCount }] = await Promise.all([
    supabase.from('provider_credentials').select('*', { count: 'exact', head: true }).eq('credential_type_id', id),
    supabase.from('credential_submissions').select('*', { count: 'exact', head: true }).eq('credential_type_id', id),
  ])

  const requirementRows = (requirements ?? []) as any[]
  const requirementAgencyChoices = credential.scope_type === 'agency'
    ? context.manageableAgencies.filter((a:any) => a.id === credential.agency_id)
    : context.manageableAgencies
  const canAddRequirement = context.isSystemAdmin || requirementAgencyChoices.length > 0
  const ownerLabel = credential.scope_type === 'system' ? 'GEAEMS System' : credential.agencies?.name ?? 'Agency'

  return <>
    <PageHeader title={credential.name} description={`${ownerLabel} credential · ${credential.category}`} action={<Link className="secondary-button button-link" href="/credentials">Back to credentials</Link>} />
    {saved && <div className="banner success"><div><strong>Credential saved</strong><span>Your changes are active.</span></div></div>}
    {notice && <div className="banner success"><div><strong>Credential updated</strong><span>{notice}</span></div></div>}
    {error && <div className="banner danger"><div><strong>Credential action failed</strong><span>{error}</span></div></div>}

    <div className="summary-strip">
      <div><span>Owner</span><strong>{ownerLabel}</strong></div>
      <div><span>Requirements</span><strong>{requirementRows.length}</strong></div>
      <div><span>Provider records</span><strong>{recordCount ?? 0}</strong></div>
      <div><span>Submissions</span><strong>{submissionCount ?? 0}</strong></div>
    </div>

    {canEditDefinition ? <form action={updateCredentialType} className="form-card">
      <input type="hidden" name="id" value={id} />
      <div className="form-card-heading"><div><span>Credential definition</span><h2>Identity and renewal rules</h2></div><span className={`pill ${credential.active ? 'green' : ''}`}>{credential.active ? 'Active' : 'Inactive'}</span></div>
      <div className="banner neutral"><div><strong>{credential.scope_type === 'system' ? 'System credential' : 'Agency credential'}</strong><span>Owned by {ownerLabel}. Credential ownership is fixed after creation so historical compliance data cannot silently change scope.</span></div></div>
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
      <div className="form-actions"><button className="primary-button" type="submit">Save changes</button></div>
    </form> : <section className="form-card compact-card">
      <div className="form-card-heading"><div><span>Credential definition</span><h2>System-managed credential</h2></div><span className={`pill ${credential.active ? 'green' : ''}`}>{credential.active ? 'Active' : 'Inactive'}</span></div>
      <dl className="detail-list">
        <div><dt>Owner</dt><dd>{ownerLabel}</dd></div><div><dt>Code</dt><dd>{credential.code}</dd></div><div><dt>Category</dt><dd>{credential.category}</dd></div><div><dt>Renewal</dt><dd>{credential.renewal_months ? `${credential.renewal_months} months` : 'Variable'}</dd></div><div><dt>Verification</dt><dd>{credential.requires_verification ? 'Required' : 'Not required'}</dd></div><div><dt>Expiration date</dt><dd>{credential.requires_expiration_date ? 'Required' : 'Optional'}</dd></div>
      </dl>
      {credential.description && <p className="panel-copy">{credential.description}</p>}
      <p className="panel-copy">Agency Administrators cannot alter a System credential definition, but may add an agency-specific requirement below.</p>
    </section>}

    <section className="section-block">
      <div className="section-title"><div><span>Compliance rules</span><h2>Who is required to maintain this credential?</h2></div><div className="section-badge">{requirementRows.length} requirement{requirementRows.length === 1 ? '' : 's'}</div></div>
      <div className="table-card">{requirementRows.length === 0 ? <div className="empty-state compact"><strong>No requirements configured</strong><span>This credential is currently tracked only when manually entered. Add a requirement to include providers in compliance calculations.</span></div> : <table>
        <thead><tr><th>Scope</th><th>Applies to</th><th>Effective</th><th>Notes</th><th></th></tr></thead>
        <tbody>{requirementRows.map((r:any) => {
          const manageable = context.isSystemAdmin || (r.scope_type === 'agency' && canManageAgency(context.manageableAgencies, r.agency_id))
          const scope = r.scope_type === 'system' ? 'GEAEMS System' : (r.agencies?.name ?? 'Agency')
          const applies = r.provider_levels?.name ?? (r.scope_type === 'system' ? 'All active system providers' : 'All active agency providers')
          const effective = r.effective_start_date || r.effective_end_date ? `${r.effective_start_date ?? 'Now'} – ${r.effective_end_date ?? 'No end'}` : 'Current / ongoing'
          return <tr key={r.id}><td><strong>{scope}</strong><div className="muted-code">{r.scope_type === 'system' ? 'SYSTEM' : 'AGENCY'}</div></td><td>{applies}</td><td>{effective}</td><td>{r.notes || '—'}</td><td className="table-action">{manageable && <form action={deleteCredentialRequirement}><input type="hidden" name="requirement_id" value={r.id}/><input type="hidden" name="credential_type_id" value={id}/><button className="text-button danger-text" type="submit">Remove</button></form>}</td></tr>
        })}</tbody>
      </table>}</div>
    </section>

    {canAddRequirement && <section className="form-card compact-card">
      <div className="form-card-heading"><div><span>Requirement</span><h2>Add compliance requirement</h2></div></div>
      <form action={createCredentialRequirement}>
        <input type="hidden" name="credential_type_id" value={id}/>
        <div className="form-grid three">
          {context.isSystemAdmin && credential.scope_type === 'system' ? <label className="field"><span>Requirement scope *</span><select name="requirement_scope" defaultValue="system"><option value="system">GEAEMS System</option><option value="agency">Specific agency</option></select></label> : <><input type="hidden" name="requirement_scope" value="agency"/><label className="field"><span>Requirement scope</span><input value="Agency" disabled /></label></>}
          <label className="field"><span>Agency{context.isSystemAdmin && credential.scope_type === 'system' ? '' : ' *'}</span><select name="requirement_agency_id" defaultValue={credential.scope_type === 'agency' ? credential.agency_id ?? '' : (requirementAgencyChoices.length === 1 && !context.isSystemAdmin ? requirementAgencyChoices[0].id : '')}><option value="">Not applicable / System-wide</option>{requirementAgencyChoices.map((a:any) => <option key={a.id} value={a.id}>{a.name}</option>)}</select><small>Used only for an Agency requirement.</small></label>
          <label className="field"><span>Provider level</span><select name="provider_level_id" defaultValue=""><option value="">All provider levels</option>{(levels ?? []).map((l:any) => <option key={l.id} value={l.id}>{l.name}</option>)}</select></label>
          <label className="field"><span>Effective start</span><input type="date" name="effective_start_date" /></label>
          <label className="field"><span>Effective end</span><input type="date" name="effective_end_date" /></label>
          <label className="field"><span>Notes</span><input name="requirement_notes" placeholder="Optional administrative note" /></label>
        </div>
        <div className="form-actions"><button className="primary-button" type="submit">Add requirement</button></div>
      </form>
    </section>}

    {canEditDefinition && <section className="form-card compact-card danger-zone">
      <div className="form-card-heading"><div><span>{context.isSystemAdmin ? 'Permanent deletion' : 'Retire credential'}</span><h2>{context.isSystemAdmin ? 'Delete credential type' : 'Deactivate agency credential'}</h2></div></div>
      <p className="panel-copy">This credential currently has <strong>{recordCount ?? 0}</strong> provider record(s), <strong>{requirementRows.length}</strong> visible requirement(s), and <strong>{submissionCount ?? 0}</strong> submission(s). {context.isSystemAdmin ? 'If it is referenced anywhere, the portal will deactivate it instead of destroying history.' : 'Agency credentials are retired rather than permanently deleted so historical compliance data is preserved.'}</p>
      <form action={deleteCredentialType}><input type="hidden" name="id" value={id} /><button className="secondary-button danger-outline" type="submit">{context.isSystemAdmin ? 'Delete credential type' : 'Deactivate credential'}</button></form>
    </section>}
  </>
}
