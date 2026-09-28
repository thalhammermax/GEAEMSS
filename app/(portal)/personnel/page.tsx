import type { Metadata } from 'next'
import { createClient } from '@/lib/supabase/server'
import { PageHeader } from '@/components/page-header'

export const metadata: Metadata = { title: 'Personnel' }

export default async function PersonnelPage() {
  const supabase = await createClient()
  const { data, error } = await supabase.from('providers').select('id, provider_number, first_name, last_name, email, provider_levels(name), provider_statuses(name)').order('last_name').order('first_name').limit(250)
  const rows = (data ?? []) as any[]
  return <><PageHeader title="Personnel" description="System provider registry and agency affiliations." action={<button className="primary-button small" disabled>Add provider</button>} />
    <div className="table-card">{error ? <div className="empty-state danger-text">{error.message}</div> : rows.length === 0 ? <div className="empty-state"><strong>No providers yet</strong><span>Your database is connected. Provider records will appear here after import or entry.</span></div> : <table><thead><tr><th>Provider</th><th>System ID</th><th>Level</th><th>Status</th><th>Email</th></tr></thead><tbody>{rows.map((r) => <tr key={r.id}><td><strong>{r.last_name}, {r.first_name}</strong></td><td>{r.provider_number || '—'}</td><td>{r.provider_levels?.name || '—'}</td><td><span className="pill">{r.provider_statuses?.name || 'Unassigned'}</span></td><td>{r.email || '—'}</td></tr>)}</tbody></table>}</div></>
}
