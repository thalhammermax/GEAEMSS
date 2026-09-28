import type { Metadata } from 'next'
import Link from 'next/link'
import { notFound } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { PageHeader } from '@/components/page-header'
import { formatDate } from '@/lib/format'
import { addAffiliation, endAffiliation, setPrimaryAffiliation } from '../actions'

export const metadata: Metadata = { title: 'Provider Profile' }
type Props = { params: Promise<{ id: string }>; searchParams: Promise<{ error?: string; saved?: string }> }

function credentialState(expiration: string | null) {
  if (!expiration) return { label: 'Current', className: 'green' }
  const today = new Date(); today.setHours(0, 0, 0, 0)
  const end = new Date(`${expiration}T12:00:00`)
  const days = Math.ceil((end.getTime() - today.getTime()) / 86400000)
  if (days < 0) return { label: 'Expired', className: 'red' }
  if (days <= 30) return { label: `${days}d`, className: 'red' }
  if (days <= 90) return { label: `${days}d`, className: 'amber' }
  return { label: 'Current', className: 'green' }
}

export default async function ProviderPage({ params, searchParams }: Props) {
  const { id } = await params
  const qs = await searchParams
  const supabase = await createClient()
  const [{ data: provider, error }, { data: affiliations }, { data: agencies }, { data: levels }, { data: credentials }] = await Promise.all([
    supabase.from('providers').select('*, provider_levels(name), provider_statuses(name)').eq('id', id).maybeSingle(),
    supabase.from('provider_agencies').select('id, agency_id, employee_id, start_date, end_date, is_primary, active, agencies(id, name, short_name), provider_levels:agency_provider_level_id(name)').eq('provider_id', id).order('active', { ascending: false }).order('is_primary', { ascending: false }).order('start_date', { ascending: false }),
    supabase.from('agencies').select('id, name').eq('active', true).order('name'),
    supabase.from('provider_levels').select('id, name').eq('active', true).order('sort_order'),
    supabase.from('provider_credentials').select('id, credential_number, issue_date, expiration_date, is_current, verification_status, credential_types(name, category)').eq('provider_id', id).eq('is_current', true).eq('verification_status', 'verified').order('expiration_date'),
  ])
  if (error || !provider) notFound()

  const affiliationRows = (affiliations ?? []) as any[]
  const activeAgencyIds = new Set(affiliationRows.filter((a) => a.active).map((a) => a.agency_id))
  const availableAgencies = (agencies ?? []).filter((a) => !activeAgencyIds.has(a.id))
  const credentialRows = (credentials ?? []) as any[]

  return <>
    <PageHeader eyebrow="Personnel" title={`${provider.first_name} ${provider.last_name}`} description={`${provider.provider_levels?.name ?? 'Provider'} · ${provider.provider_number || 'No system ID assigned'}`} action={<Link className="primary-button small button-link" href={`/personnel/${provider.id}/edit`}>Edit provider</Link>} />
    {qs.saved && <div className="banner success"><div><strong>Saved</strong><span>The provider record was updated.</span></div></div>}
    {qs.error && <div className="banner danger"><div><strong>Unable to save</strong><span>{qs.error}</span></div></div>}

    <div className="profile-grid">
      <section className="panel profile-summary">
        <div className="profile-avatar">{provider.first_name.slice(0, 1)}{provider.last_name.slice(0, 1)}</div>
        <div><h2>{provider.preferred_name || provider.first_name} {provider.last_name}</h2><span className="pill green">{provider.provider_statuses?.name || 'Unassigned'}</span></div>
        <dl className="detail-list">
          <div><dt>System ID</dt><dd>{provider.provider_number || '—'}</dd></div>
          <div><dt>Provider level</dt><dd>{provider.provider_levels?.name || '—'}</dd></div>
          <div><dt>System entry</dt><dd>{formatDate(provider.system_entry_date)}</dd></div>
          <div><dt>Email</dt><dd>{provider.email ? <a href={`mailto:${provider.email}`}>{provider.email}</a> : '—'}</dd></div>
          <div><dt>Phone</dt><dd>{provider.phone || '—'}</dd></div>
        </dl>
        {provider.notes && <div className="notes-box"><span>Notes</span><p>{provider.notes}</p></div>}
      </section>

      <section className="panel">
        <div className="panel-heading"><h3>Current credentials</h3><span>{credentialRows.length} records</span></div>
        {credentialRows.length === 0 ? <div className="empty-state compact"><strong>No credentials entered</strong><span>Credential entry and renewal workflows are the next module.</span></div> : <div className="credential-mini-list">{credentialRows.map((credential) => {
          const state = credentialState(credential.expiration_date)
          return <div key={credential.id}><div><strong>{credential.credential_types?.name}</strong><span>{credential.credential_number || credential.credential_types?.category || ''}</span></div><div className="credential-date"><span>{formatDate(credential.expiration_date)}</span><span className={`pill ${state.className}`}>{state.label}</span></div></div>
        })}</div>}
      </section>
    </div>

    <section className="section-block">
      <div className="section-title"><div><span>Employment</span><h2>Agency affiliations</h2></div><div className="section-badge">{affiliationRows.filter((a) => a.active).length} active</div></div>
      <div className="table-card">{affiliationRows.length === 0 ? <div className="empty-state compact"><strong>No affiliations</strong></div> : <table>
        <thead><tr><th>Agency</th><th>Employee ID</th><th>Agency level</th><th>Start</th><th>End</th><th>Status</th><th>Actions</th></tr></thead>
        <tbody>{affiliationRows.map((row) => <tr key={row.id}><td><strong>{row.agencies?.name}</strong>{row.is_primary && row.active && <div className="muted-code">Primary agency</div>}</td><td>{row.employee_id || '—'}</td><td>{row.provider_levels?.name || '—'}</td><td>{formatDate(row.start_date)}</td><td>{formatDate(row.end_date)}</td><td><span className={`pill ${row.active ? 'green' : ''}`}>{row.active ? 'Active' : 'Ended'}</span></td><td className="inline-actions">{row.active && !row.is_primary && <form action={setPrimaryAffiliation}><input type="hidden" name="provider_id" value={provider.id} /><input type="hidden" name="affiliation_id" value={row.id} /><button className="text-button" type="submit">Make primary</button></form>}{row.active && <form action={endAffiliation}><input type="hidden" name="provider_id" value={provider.id} /><input type="hidden" name="affiliation_id" value={row.id} /><button className="text-button danger-text" type="submit">End</button></form>}</td></tr>)}</tbody>
      </table>}</div>
    </section>

    <section className="form-card compact-card">
      <div className="form-card-heading"><div><span>Affiliation</span><h2>Add another agency</h2></div></div>
      {availableAgencies.length === 0 ? <p className="panel-copy">This provider is already affiliated with every active agency currently visible to your account.</p> : <form action={addAffiliation}>
        <input type="hidden" name="provider_id" value={provider.id} />
        <div className="form-grid four">
          <label className="field"><span>Agency *</span><select name="agency_id" required defaultValue=""><option value="" disabled>Select agency</option>{availableAgencies.map((a) => <option key={a.id} value={a.id}>{a.name}</option>)}</select></label>
          <label className="field"><span>Employee ID</span><input name="employee_id" /></label>
          <label className="field"><span>Agency level</span><select name="agency_provider_level_id" defaultValue=""><option value="">Same / unspecified</option>{levels?.map((l) => <option key={l.id} value={l.id}>{l.name}</option>)}</select></label>
          <label className="field"><span>Start date</span><input name="start_date" type="date" /></label>
        </div>
        <label className="checkbox-field"><input name="is_primary" type="checkbox" /><span>Make this the provider's primary agency</span></label>
        <div className="form-actions"><button className="primary-button" type="submit">Add affiliation</button></div>
      </form>}
    </section>
  </>
}
