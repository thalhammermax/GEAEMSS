import type { Metadata } from 'next'
import Link from 'next/link'
import { createClient } from '@/lib/supabase/server'
import { PageHeader } from '@/components/page-header'
import { getModuleStates } from '@/lib/modules'

export const metadata: Metadata = { title: 'Administration' }

export default async function AdministrationPage() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  const [agencies, levels, statuses, vehicleTypes, inspectionTypes, fields, users, credentialTypes, roles, moduleStates] = await Promise.all([
    supabase.from('agencies').select('id, name, short_name, active').order('name'),
    supabase.from('provider_levels').select('*', { count: 'exact', head: true }),
    supabase.from('provider_statuses').select('*', { count: 'exact', head: true }),
    supabase.from('vehicle_types').select('*', { count: 'exact', head: true }),
    supabase.from('inspection_types').select('*', { count: 'exact', head: true }),
    supabase.from('record_field_definitions').select('*', { count: 'exact', head: true }).eq('source_type', 'custom'),
    supabase.from('profiles').select('*', { count: 'exact', head: true }),
    supabase.from('credential_types').select('*', { count: 'exact', head: true }),
    user ? supabase.from('user_roles').select('role').eq('user_id', user.id) : Promise.resolve({ data: [] } as any),
    getModuleStates(supabase),
  ])

  const roleNames = new Set((roles.data ?? []).map((row: any) => row.role))
  const isSystemAdmin = roleNames.has('system_admin')
  const currentAgencies = (agencies.data ?? []).filter((agency: any) => agency.active)
  const archivedAgencyCount = (agencies.data ?? []).filter((agency: any) => !agency.active).length

  return <>
    <PageHeader title="Administration" description="System configuration, agencies, field definitions, lookup values, module rollout and access control." />
    <div className="summary-strip"><div><span>Active agencies</span><strong>{currentAgencies.length}</strong></div>{(moduleStates.personnel || isSystemAdmin) && <div><span>Provider levels</span><strong>{levels.count ?? 0}</strong></div>}{(moduleStates.personnel || isSystemAdmin) && <div><span>Provider statuses</span><strong>{statuses.count ?? 0}</strong></div>}<div><span>Vehicle types</span><strong>{vehicleTypes.count ?? 0}</strong></div><div><span>Inspection types</span><strong>{inspectionTypes.count ?? 0}</strong></div><div><span>Custom fields</span><strong>{fields.count ?? 0}</strong></div><div><span>Portal users</span><strong>{users.count ?? 0}</strong></div>{(moduleStates.credentials || isSystemAdmin) && <div><span>Credential types</span><strong>{credentialTypes.count ?? 0}</strong></div>}</div>

    <div className="admin-card-grid">
      {isSystemAdmin && <Link className="admin-card" href="/administration/modules"><span>Rollout</span><strong>Module Controls</strong><p>Turn portal modules on or off as GEAEMS phases each workflow into production.</p><b>Manage modules →</b></Link>}
      <Link className="admin-card" href="/administration/agencies"><span>Organizations</span><strong>Agencies</strong><p>Create and maintain participating agencies, archive test organizations, and preserve historical records.</p><b>Manage agencies{archivedAgencyCount ? ` · ${archivedAgencyCount} archived` : ''} →</b></Link>
      <Link className="admin-card" href="/administration/fields"><span>Records</span><strong>Field Configuration</strong><p>Enable, disable or require built-in fields and create custom fields for personnel, agencies and vehicles.</p><b>Configure fields →</b></Link>
      <Link className="admin-card" href="/administration/users"><span>Access</span><strong>User Management</strong><p>Invite accounts, manage roles, disable access and assign agency administration permissions.</p><b>Manage users →</b></Link>
      {(moduleStates.credentials || isSystemAdmin) && <Link className="admin-card" href="/credentials"><span>Compliance</span><strong>Credential Definitions</strong><p>Create, edit, activate and retire the credential types used throughout the system.</p><b>{moduleStates.credentials ? 'Manage credentials' : 'Prepare disabled module'} →</b></Link>}
      {(moduleStates.narcotics || isSystemAdmin) && <Link className="admin-card" href="/narcotics/settings"><span>Operations</span><strong>Narcotics Management</strong><p>Configure daily count templates, agency reporting times, and controlled-substance inventory workflows.</p><b>{moduleStates.narcotics ? 'Configure narcotics' : 'Prepare disabled module'} →</b></Link>}
    </div>

    <section className="panel"><div className="panel-heading"><h3>Current agencies</h3><span>Active system organizations</span></div>{currentAgencies.length === 0 ? <div className="empty-state compact"><strong>No active agencies configured yet</strong><span>Add or restore a participating agency before loading production fleet records.</span></div> : <div className="agency-list">{currentAgencies.map((a: any) => <div key={a.id}><span className="status-dot active"/><Link href={`/administration/agencies/${a.id}`}><strong>{a.name}</strong></Link><span>{a.short_name || ''}</span></div>)}</div>}{archivedAgencyCount > 0 && <p className="panel-copy"><Link href="/administration/agencies?view=archived">View {archivedAgencyCount} archived agenc{archivedAgencyCount === 1 ? 'y' : 'ies'} →</Link></p>}</section>
  </>
}
