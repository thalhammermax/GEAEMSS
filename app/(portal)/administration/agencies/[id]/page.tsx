import type { Metadata } from 'next'
import Link from 'next/link'
import { notFound } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { PageHeader } from '@/components/page-header'
import { CustomFieldInputs } from '@/components/custom-field-inputs'
import { builtinFieldMap, fetchCustomFieldValues, fetchFieldDefinitions, isEnabled, isRequired } from '@/lib/record-fields'
import { setAgencyActive, updateAgency } from '../actions'

export const metadata: Metadata = { title: 'Agency' }
type Props = { params: Promise<{ id: string }>; searchParams: Promise<{ error?: string; saved?: string }> }

export default async function AgencyPage({ params, searchParams }: Props) {
  const { id } = await params
  const qs = await searchParams
  const supabase = await createClient()
  const [{ data: agency, error }, { data: roster }, fieldResult, valueResult] = await Promise.all([
    supabase.from('agencies').select('id, name, short_name, address, active').eq('id', id).maybeSingle(),
    supabase.from('provider_agencies').select('id, employee_id, is_primary, providers(id, first_name, last_name, provider_number, provider_levels(name), provider_statuses(name))').eq('agency_id', id).eq('active', true),
    fetchFieldDefinitions(supabase, 'agency'),
    fetchCustomFieldValues(supabase, id),
  ])
  if (error || !agency) notFound()
  const people = (roster ?? []) as any[]
  people.sort((a, b) => `${a.providers?.last_name ?? ''}${a.providers?.first_name ?? ''}`.localeCompare(`${b.providers?.last_name ?? ''}${b.providers?.first_name ?? ''}`))
  const map = builtinFieldMap(fieldResult.fields)
  const custom = fieldResult.fields.filter((field) => field.source_type === 'custom')
  const req = (key: string, fallback = false) => isRequired(map, key, fallback)

  return <>
    <PageHeader eyebrow="Agency Administration" title={agency.name} description="Agency details and active provider roster." action={<Link className="secondary-button button-link" href={`/personnel?agency=${agency.id}`}>View personnel</Link>} />
    {qs.saved && <div className="banner success"><div><strong>{qs.saved === 'archived' ? 'Agency archived' : qs.saved === 'restored' ? 'Agency restored' : 'Saved'}</strong><span>{qs.saved === 'archived' ? 'The agency is now excluded from normal production workflows. Its historical records and attached records remain intact.' : qs.saved === 'restored' ? 'The agency is active again. Active vehicles and other current records under the agency are available to production workflows again.' : 'Agency information was updated.'}</span></div></div>}
    {!agency.active && <div className="banner info"><div><strong>Archived agency</strong><span>This organization remains available for history, but it and its apparatus are excluded from current fleet, new inspections, compliance dashboards and standard operational reports.</span></div></div>}
    {qs.error && <div className="banner danger"><div><strong>Unable to save</strong><span>{qs.error}</span></div></div>}

    <div className="dashboard-columns detail-columns">
      <form action={updateAgency} className="form-card">
        <input type="hidden" name="id" value={agency.id} />
        <div className="form-card-heading"><div><span>Configuration</span><h2>Agency details</h2></div><span className={`pill ${agency.active ? 'green' : 'gray'}`}>{agency.active ? 'Active' : 'Archived'}</span></div>
        <div className="form-grid">
          {isEnabled(map,'name') && <label className="field"><span>Agency name{req('name',true) ? ' *' : ''}</span><input name="name" defaultValue={agency.name} required={req('name',true)} /></label>}
          {isEnabled(map,'short_name') && <label className="field"><span>Abbreviation{req('short_name') ? ' *' : ''}</span><input name="short_name" defaultValue={agency.short_name ?? ''} required={req('short_name')} /></label>}
          {isEnabled(map,'address') && <label className="field span-two"><span>Agency address{req('address') ? ' *' : ''}</span><textarea name="address" rows={2} defaultValue={agency.address ?? ''} required={req('address')} placeholder="123 Main St, Elgin, IL 60120" /><small>This is also used as the Agency Headquarters location on inspections when selected.</small></label>}
        </div>
        <CustomFieldInputs fields={custom} values={valueResult.values} />
        <div className="form-actions"><button className="primary-button" type="submit">Save changes</button></div>
      </form>

      <section className="panel">
        <div className="panel-heading"><h3>Agency status</h3><span>Archive without deleting history</span></div>
        <p className="panel-copy">Archiving preserves the agency, provider affiliations, vehicles, inspections, licenses and audit history. Current records beneath the agency are removed from normal production workflows until the agency is restored.</p>
        <form action={setAgencyActive}>
          <input type="hidden" name="id" value={agency.id} />
          <input type="hidden" name="active" value={agency.active ? 'false' : 'true'} />
          <button className={agency.active ? 'secondary-button danger-outline' : 'primary-button'} type="submit">{agency.active ? 'Archive agency' : 'Restore agency'}</button>
        </form>
      </section>
    </div>

    <section className="section-block">
      <div className="section-title"><div><span>Roster</span><h2>Active providers</h2></div><div className="section-badge">{people.length} providers</div></div>
      <div className="table-card">{people.length === 0 ? <div className="empty-state compact"><strong>No active providers</strong><span>Providers assigned to this agency will appear here.</span></div> : <table>
        <thead><tr><th>Provider</th><th>System ID</th><th>Agency employee ID</th><th>Level</th><th>Status</th><th></th></tr></thead>
        <tbody>{people.map((row) => <tr key={row.id}><td><strong>{row.providers?.last_name}, {row.providers?.first_name}</strong>{row.is_primary && <div className="muted-code">Primary agency</div>}</td><td>{row.providers?.provider_number || '—'}</td><td>{row.employee_id || '—'}</td><td>{row.providers?.provider_levels?.name || '—'}</td><td><span className="pill">{row.providers?.provider_statuses?.name || '—'}</span></td><td className="table-action"><Link href={`/personnel/${row.providers?.id}`}>Open</Link></td></tr>)}</tbody>
      </table>}</div>
    </section>
  </>
}
