import type { Metadata } from 'next'
import Link from 'next/link'
import { createClient } from '@/lib/supabase/server'
import { PageHeader } from '@/components/page-header'
import { dateInTimeZone, relationOne } from '@/lib/narcotics'

export const metadata: Metadata = { title: 'Narcotics Management' }

export default async function NarcoticsPage() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return null
  const { data: profile } = await supabase.from('profiles').select('provider_id').eq('id', user.id).maybeSingle()
  const [{ data: roles }, { data: vehicles }, { data: settings }, { data: memberships }, { data: recent }] = await Promise.all([
    supabase.from('user_roles').select('role').eq('user_id', user.id),
    supabase.from('vehicles').select('id, agency_id, unit_number, fleet_number, narcotics_count_required, narcotics_template_id, agencies(name, short_name), vehicle_types(name)').eq('active', true).eq('narcotics_count_required', true).order('unit_number'),
    supabase.from('narcotics_agency_settings').select('*'),
    profile?.provider_id ? supabase.from('provider_agencies').select('agency_id').eq('provider_id', profile.provider_id).eq('active', true) : Promise.resolve({ data: [] as any[] }),
    supabase.from('narcotics_counts').select('id, agency_id, vehicle_id, count_date, status, has_discrepancy, signed_name, signed_at').order('count_date', { ascending: false }).limit(200),
  ])
  const roleNames = new Set((roles ?? []).map((r:any) => r.role))
  const canConfigure = roleNames.has('system_admin') || roleNames.has('agency_admin')
  const memberAgencies = new Set((memberships ?? []).map((m:any) => m.agency_id))
  const settingMap = new Map((settings ?? []).map((s:any) => [s.agency_id, s]))
  const rows = (vehicles ?? []).map((vehicle:any) => {
    const agency = relationOne<any>(vehicle.agencies)
    const type = relationOne<any>(vehicle.vehicle_types)
    const setting:any = settingMap.get(vehicle.agency_id)
    const date = dateInTimeZone(setting?.timezone || 'America/Chicago')
    const count = (recent ?? []).find((c:any) => c.vehicle_id === vehicle.id && c.count_date === date)
    return { ...vehicle, agency, type, setting, localDate: date, count, canCount: memberAgencies.has(vehicle.agency_id) }
  }).filter((row:any) => row.setting?.enabled !== false)
  const submitted = rows.filter((r:any) => r.count?.status === 'submitted').length
  const incomplete = rows.length - submitted
  const discrepancies = rows.filter((r:any) => r.count?.status === 'submitted' && r.count?.has_discrepancy).length

  return <>
    <PageHeader title="Narcotics Management" description="Daily controlled-substance inventory counts for ALS apparatus." action={canConfigure ? <Link className="secondary-button button-link" href="/narcotics/settings">Templates & settings</Link> : undefined} />
    <div className="summary-strip"><div><span>Required apparatus</span><strong>{rows.length}</strong></div><div><span>Submitted today</span><strong>{submitted}</strong></div><div><span>Incomplete</span><strong>{incomplete}</strong></div><div><span>Discrepancies</span><strong>{discrepancies}</strong></div></div>
    <div className="table-card">{rows.length === 0 ? <div className="empty-state"><strong>No narcotics-count apparatus are visible to you.</strong><span>ALS apparatus can be enabled from the Fleet record.</span></div> : <table><thead><tr><th>Unit</th><th>Agency</th><th>Vehicle type</th><th>Date</th><th>Status</th><th></th></tr></thead><tbody>{rows.map((r:any) => <tr key={r.id}><td><strong>{r.unit_number || r.fleet_number || 'Unnumbered'}</strong></td><td>{r.agency?.short_name || r.agency?.name || '—'}</td><td>{r.type?.name || '—'}</td><td>{r.localDate}</td><td>{r.count?.status === 'submitted' ? <span className={`pill ${r.count.has_discrepancy ? 'amber' : 'green'}`}>{r.count.has_discrepancy ? 'Submitted · discrepancy' : 'Submitted'}</span> : r.count?.status === 'draft' ? <span className="pill amber">Draft</span> : <span className="pill red">Incomplete</span>}</td><td className="table-action">{r.count?.status === 'submitted' ? <Link href={`/narcotics/${r.count.id}`}>View</Link> : r.canCount ? <Link href={`/narcotics/count/${r.id}`}>{r.count?.status === 'draft' ? 'Resume' : 'Start count'}</Link> : <span className="muted-code">View only</span>}</td></tr>)}</tbody></table>}</div>
  </>
}
