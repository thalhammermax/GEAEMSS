import type { Metadata } from 'next'
import { createClient } from '@/lib/supabase/server'
import { PageHeader } from '@/components/page-header'

export const metadata: Metadata = { title: 'Administration' }
export default async function AdministrationPage() {
  const supabase = await createClient()
  const [agencies, levels, statuses, vehicleTypes, inspectionTypes] = await Promise.all([
    supabase.from('agencies').select('id, name, short_name, active').order('name'),
    supabase.from('provider_levels').select('*', { count: 'exact', head: true }),
    supabase.from('provider_statuses').select('*', { count: 'exact', head: true }),
    supabase.from('vehicle_types').select('*', { count: 'exact', head: true }),
    supabase.from('inspection_types').select('*', { count: 'exact', head: true }),
  ])
  return <><PageHeader title="Administration" description="System configuration, agencies, lookup values and access control." />
    <div className="summary-strip"><div><span>Agencies</span><strong>{agencies.data?.length ?? 0}</strong></div><div><span>Provider levels</span><strong>{levels.count ?? 0}</strong></div><div><span>Provider statuses</span><strong>{statuses.count ?? 0}</strong></div><div><span>Vehicle types</span><strong>{vehicleTypes.count ?? 0}</strong></div><div><span>Inspection types</span><strong>{inspectionTypes.count ?? 0}</strong></div></div>
    <section className="panel"><div className="panel-heading"><h3>Agencies</h3><span>System organizations</span></div>{(agencies.data?.length ?? 0) === 0 ? <div className="empty-state compact"><strong>No agencies configured yet</strong><span>Agency management is the next configuration step.</span></div> : <div className="agency-list">{agencies.data?.map((a: any) => <div key={a.id}><span className={`status-dot ${a.active ? 'active' : ''}`}/><strong>{a.name}</strong><span>{a.short_name || ''}</span></div>)}</div>}</section>
  </>
}
