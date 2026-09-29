import type { Metadata } from 'next'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { PageHeader } from '@/components/page-header'
import { formatDate } from '@/lib/format'
import { fetchCustomFieldValues, fetchFieldDefinitions } from '@/lib/record-fields'

export const metadata: Metadata = { title: 'My Profile' }

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

function displayCustomValue(value: unknown) {
  if (Array.isArray(value)) return value.join(', ') || '—'
  if (typeof value === 'boolean') return value ? 'Yes' : 'No'
  if (value === null || value === undefined || value === '') return '—'
  return String(value)
}

export default async function MyProfilePage() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const { data: profile } = await supabase.from('profiles').select('provider_id').eq('id', user.id).maybeSingle()
  if (!profile?.provider_id) redirect('/auth/disabled')
  const id = profile.provider_id

  const [
    { data: provider, error },
    { data: affiliations },
    { data: credentials },
    { fields },
    { values: customValues },
  ] = await Promise.all([
    supabase.from('providers').select('id, provider_number, first_name, middle_name, last_name, preferred_name, email, phone, system_entry_date, provider_level_id, provider_status_id, provider_levels(name), provider_statuses(name)').eq('id', id).maybeSingle(),
    supabase.from('provider_agencies').select('id, employee_id, start_date, end_date, is_primary, active, agencies(id, name, short_name), provider_levels:agency_provider_level_id(name)').eq('provider_id', id).order('active', { ascending: false }).order('is_primary', { ascending: false }).order('start_date', { ascending: false }),
    supabase.from('provider_credentials').select('id, credential_number, issue_date, expiration_date, is_current, verification_status, credential_types(name, category)').eq('provider_id', id).eq('is_current', true).eq('verification_status', 'verified').order('expiration_date'),
    fetchFieldDefinitions(supabase, 'provider'),
    fetchCustomFieldValues(supabase, id),
  ])

  if (error || !provider) redirect('/auth/disabled')
  const affiliationRows = (affiliations ?? []) as any[]
  const credentialRows = (credentials ?? []) as any[]
  const visibleCustomFields = fields.filter((field) => field.source_type === 'custom' && field.enabled && customValues.has(field.id))

  return <>
    <PageHeader eyebrow="Provider Self-Service" title="My Profile" description="Your GEAEMS System provider record. Contact System Administration if information needs to be corrected." />

    <div className="profile-grid">
      <section className="panel profile-summary">
        <div className="profile-avatar">{provider.first_name.slice(0, 1)}{provider.last_name.slice(0, 1)}</div>
        <div><h2>{provider.preferred_name || provider.first_name} {provider.last_name}</h2><span className="pill green">{(provider.provider_statuses as any)?.name || 'Unassigned'}</span></div>
        <dl className="detail-list">
          <div><dt>System ID</dt><dd>{provider.provider_number || '—'}</dd></div>
          <div><dt>Provider level</dt><dd>{(provider.provider_levels as any)?.name || '—'}</dd></div>
          <div><dt>System entry</dt><dd>{formatDate(provider.system_entry_date)}</dd></div>
          <div><dt>Email / username</dt><dd>{provider.email || user.email || '—'}</dd></div>
          <div><dt>Phone</dt><dd>{provider.phone || '—'}</dd></div>
        </dl>
      </section>

      <section className="panel">
        <div className="panel-heading"><h3>Current credentials</h3><span>{credentialRows.length} records</span></div>
        {credentialRows.length === 0 ? <div className="empty-state compact"><strong>No credentials entered</strong><span>No verified current credentials are on your provider record.</span></div> : <div className="credential-mini-list">{credentialRows.map((credential) => {
          const state = credentialState(credential.expiration_date)
          return <div key={credential.id}><div><strong>{credential.credential_types?.name}</strong><span>{credential.credential_number || credential.credential_types?.category || ''}</span></div><div className="credential-date"><span>{formatDate(credential.expiration_date)}</span><span className={`pill ${state.className}`}>{state.label}</span></div></div>
        })}</div>}
      </section>
    </div>

    <section className="section-block">
      <div className="section-title"><div><span>Affiliations</span><h2>My agencies</h2></div><div className="section-badge">{affiliationRows.filter((a) => a.active).length} active</div></div>
      <div className="table-card">{affiliationRows.length === 0 ? <div className="empty-state compact"><strong>No agency affiliations</strong></div> : <table>
        <thead><tr><th>Agency</th><th>Employee ID</th><th>Agency level</th><th>Start</th><th>End</th><th>Status</th></tr></thead>
        <tbody>{affiliationRows.map((row) => <tr key={row.id}><td><strong>{row.agencies?.name}</strong>{row.is_primary && row.active && <div className="muted-code">Primary agency</div>}</td><td>{row.employee_id || '—'}</td><td>{row.provider_levels?.name || '—'}</td><td>{formatDate(row.start_date)}</td><td>{formatDate(row.end_date)}</td><td><span className={`pill ${row.active ? 'green' : ''}`}>{row.active ? 'Active' : 'Ended'}</span></td></tr>)}</tbody>
      </table>}</div>
    </section>

    {visibleCustomFields.length > 0 && <section className="panel">
      <div className="panel-heading"><h3>Additional information</h3><span>Provider record</span></div>
      <dl className="detail-list">{visibleCustomFields.map((field) => <div key={field.id}><dt>{field.label}</dt><dd>{displayCustomValue(customValues.get(field.id))}</dd></div>)}</dl>
    </section>}
  </>
}
