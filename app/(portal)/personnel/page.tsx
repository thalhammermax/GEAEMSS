import type { Metadata } from 'next'
import Link from 'next/link'
import { createClient } from '@/lib/supabase/server'
import { PageHeader } from '@/components/page-header'

export const metadata: Metadata = { title: 'Personnel' }
type Props = { searchParams: Promise<{ q?: string; agency?: string; level?: string; status?: string }> }

export default async function PersonnelPage({ searchParams }: Props) {
  const filters = await searchParams
  const supabase = await createClient()
  const [{ data, error }, { data: agencies }, { data: levels }, { data: statuses }] = await Promise.all([
    supabase.from('providers').select('id, provider_number, first_name, last_name, preferred_name, email, provider_level_id, provider_status_id, provider_levels(name), provider_statuses(name), provider_agencies(agency_id, active, is_primary, agencies(id, name, short_name))').order('last_name').order('first_name').limit(2000),
    supabase.from('agencies').select('id, name').eq('active', true).order('name'),
    supabase.from('provider_levels').select('id, name').eq('active', true).order('sort_order'),
    supabase.from('provider_statuses').select('id, name').eq('active', true).order('name'),
  ])

  const q = (filters.q ?? '').trim().toLowerCase()
  let rows = (data ?? []) as any[]
  if (q) rows = rows.filter((r) => [r.first_name, r.last_name, r.preferred_name, r.provider_number, r.email].some((v) => String(v ?? '').toLowerCase().includes(q)))
  if (filters.level) rows = rows.filter((r) => r.provider_level_id === filters.level)
  if (filters.status) rows = rows.filter((r) => r.provider_status_id === filters.status)
  if (filters.agency) rows = rows.filter((r) => (r.provider_agencies ?? []).some((a: any) => a.active && a.agency_id === filters.agency))

  return <>
    <PageHeader title="Personnel" description="System provider registry and agency affiliations." action={<Link className="primary-button small button-link" href="/personnel/new">Add provider</Link>} />
    <form className="filter-bar" method="get">
      <label className="search-field"><span className="sr-only">Search personnel</span><input name="q" defaultValue={filters.q ?? ''} placeholder="Search name, system ID, or email" /></label>
      <select name="agency" defaultValue={filters.agency ?? ''}><option value="">All agencies</option>{agencies?.map((a) => <option key={a.id} value={a.id}>{a.name}</option>)}</select>
      <select name="level" defaultValue={filters.level ?? ''}><option value="">All levels</option>{levels?.map((l) => <option key={l.id} value={l.id}>{l.name}</option>)}</select>
      <select name="status" defaultValue={filters.status ?? ''}><option value="">All statuses</option>{statuses?.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}</select>
      <button className="secondary-button" type="submit">Filter</button>
      {(filters.q || filters.agency || filters.level || filters.status) && <Link className="text-link" href="/personnel">Clear</Link>}
    </form>
    <div className="results-meta">Showing <strong>{rows.length}</strong> provider{rows.length === 1 ? '' : 's'}</div>
    <div className="table-card">{error ? <div className="empty-state danger-text">{error.message}</div> : rows.length === 0 ? <div className="empty-state"><strong>No providers found</strong><span>Try changing the filters, or add the first provider to the system.</span></div> : <table>
      <thead><tr><th>Provider</th><th>System ID</th><th>Level</th><th>Primary agency</th><th>Status</th><th>Email</th><th></th></tr></thead>
      <tbody>{rows.map((r) => {
        const primary = (r.provider_agencies ?? []).find((a: any) => a.active && a.is_primary) ?? (r.provider_agencies ?? []).find((a: any) => a.active)
        return <tr key={r.id}><td><strong>{r.last_name}, {r.first_name}</strong>{r.preferred_name && r.preferred_name !== r.first_name && <div className="muted-code">Preferred: {r.preferred_name}</div>}</td><td>{r.provider_number || '—'}</td><td>{r.provider_levels?.name || '—'}</td><td>{primary?.agencies?.short_name || primary?.agencies?.name || '—'}</td><td><span className="pill">{r.provider_statuses?.name || 'Unassigned'}</span></td><td>{r.email || '—'}</td><td className="table-action"><Link href={`/personnel/${r.id}`}>Open</Link></td></tr>
      })}</tbody>
    </table>}</div>
  </>
}
