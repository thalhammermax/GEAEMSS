import type { Metadata } from 'next'
import { createClient } from '@/lib/supabase/server'
import { PageHeader } from '@/components/page-header'
import { StatCard } from '@/components/stat-card'
import { AlertIcon, CheckIcon } from '@/components/icons'

export const metadata: Metadata = { title: 'Dashboard' }

export default async function DashboardPage() {
  const supabase = await createClient()

  const [
    providers,
    agencies,
    vehicles,
    pending,
    expiredCredentials,
    expiringCredentials,
    missingCredentials,
    overdueInspections,
    dueInspections,
    failedInspections,
    missingInspections,
    openDeficiencies,
    criticalDeficiencies,
    expiringVehicleLicenses,
    expiredVehicleLicenses,
    missingVehicleLicenses,
  ] = await Promise.all([
    supabase.from('providers').select('*', { count: 'exact', head: true }),
    supabase.from('agencies').select('*', { count: 'exact', head: true }).eq('active', true),
    supabase.from('vehicles').select('*', { count: 'exact', head: true }).eq('active', true),
    supabase.from('credential_submissions').select('*', { count: 'exact', head: true }).eq('status', 'pending'),
    supabase.from('provider_compliance').select('*', { count: 'exact', head: true }).eq('compliance_status', 'EXPIRED'),
    supabase.from('provider_compliance').select('*', { count: 'exact', head: true }).eq('compliance_status', 'EXPIRING_SOON'),
    supabase.from('provider_compliance').select('*', { count: 'exact', head: true }).eq('compliance_status', 'MISSING'),
    supabase.from('vehicle_inspection_compliance').select('*', { count: 'exact', head: true }).eq('compliance_status', 'OVERDUE'),
    supabase.from('vehicle_inspection_compliance').select('*', { count: 'exact', head: true }).eq('compliance_status', 'DUE_SOON'),
    supabase.from('vehicle_inspection_compliance').select('*', { count: 'exact', head: true }).eq('compliance_status', 'FAILED'),
    supabase.from('vehicle_inspection_compliance').select('*', { count: 'exact', head: true }).in('compliance_status', ['MISSING', 'SCHEDULE_MISSING']),
    supabase.from('vehicle_inspection_deficiencies').select('*', { count: 'exact', head: true }).eq('status', 'open'),
    supabase.from('vehicle_inspection_deficiencies').select('*', { count: 'exact', head: true }).eq('status', 'open').eq('severity', 'critical'),
    supabase.from('vehicle_license_compliance').select('*', { count: 'exact', head: true }).eq('compliance_status', 'EXPIRING_SOON'),
    supabase.from('vehicle_license_compliance').select('*', { count: 'exact', head: true }).eq('compliance_status', 'EXPIRED'),
    supabase.from('vehicle_license_compliance').select('*', { count: 'exact', head: true }).eq('compliance_status', 'MISSING'),
  ])

  const results = [providers, agencies, vehicles, pending, expiredCredentials, expiringCredentials, missingCredentials, overdueInspections, dueInspections, failedInspections, missingInspections, openDeficiencies, criticalDeficiencies, expiringVehicleLicenses, expiredVehicleLicenses, missingVehicleLicenses]
  const firstError = results.find((r) => r.error)?.error

  const personnelIssues = (expiredCredentials.count ?? 0) + (missingCredentials.count ?? 0)
  const fleetCritical = (overdueInspections.count ?? 0) + (failedInspections.count ?? 0) + (expiredVehicleLicenses.count ?? 0) + (missingVehicleLicenses.count ?? 0)

  return <>
    <PageHeader title="System Dashboard" description="Personnel and fleet compliance across the Greater Elgin Area EMS System." />
    {firstError && <div className="banner danger"><AlertIcon/><div><strong>Some dashboard data could not be loaded.</strong><span>{firstError.message}</span></div></div>}

    <section className="section-block">
      <div className="section-title"><div><span>Personnel</span><h2>Credential readiness</h2></div><span className="section-badge">{providers.count ?? 0} providers · {agencies.count ?? 0} agencies</span></div>
      <div className="stat-grid">
        <StatCard label="Providers" value={providers.count ?? 0} detail="System personnel records" />
        <StatCard label="Expired requirements" value={expiredCredentials.count ?? 0} tone={(expiredCredentials.count ?? 0) > 0 ? 'danger' : 'success'} detail="Required credentials past expiration" />
        <StatCard label="Expiring soon" value={expiringCredentials.count ?? 0} tone={(expiringCredentials.count ?? 0) > 0 ? 'warning' : 'default'} detail="Within configured warning window" />
        <StatCard label="Missing requirements" value={missingCredentials.count ?? 0} tone={(missingCredentials.count ?? 0) > 0 ? 'danger' : 'success'} detail="No verified current credential" />
        <StatCard label="Pending verification" value={pending.count ?? 0} tone={(pending.count ?? 0) > 0 ? 'warning' : 'default'} detail="Provider renewal submissions" />
      </div>
    </section>

    <section className="section-block">
      <div className="section-title"><div><span>Fleet</span><h2>Vehicle compliance</h2></div><span className="section-badge">{vehicles.count ?? 0} active vehicles</span></div>
      <div className="stat-grid">
        <StatCard label="Active vehicles" value={vehicles.count ?? 0} detail="Across visible agencies" />
        <StatCard label="Inspections overdue" value={overdueInspections.count ?? 0} tone={(overdueInspections.count ?? 0) > 0 ? 'danger' : 'success'} detail="Past required due date" />
        <StatCard label="Inspections due soon" value={dueInspections.count ?? 0} tone={(dueInspections.count ?? 0) > 0 ? 'warning' : 'default'} detail="Within configured warning window" />
        <StatCard label="Failed / OOS inspections" value={failedInspections.count ?? 0} tone={(failedInspections.count ?? 0) > 0 ? 'danger' : 'success'} detail="Most recent required inspection" />
        <StatCard label="Missing inspections" value={missingInspections.count ?? 0} tone={(missingInspections.count ?? 0) > 0 ? 'danger' : 'success'} detail="Required inspection or schedule missing" />
        <StatCard label="Licenses expiring soon" value={expiringVehicleLicenses.count ?? 0} tone={(expiringVehicleLicenses.count ?? 0) > 0 ? 'warning' : 'default'} detail="Within configured warning window" />
        <StatCard label="Expired vehicle licenses" value={expiredVehicleLicenses.count ?? 0} tone={(expiredVehicleLicenses.count ?? 0) > 0 ? 'danger' : 'success'} detail="Required current licenses" />
        <StatCard label="Missing vehicle licenses" value={missingVehicleLicenses.count ?? 0} tone={(missingVehicleLicenses.count ?? 0) > 0 ? 'danger' : 'success'} detail="Required license record missing" />
      </div>
    </section>

    <div className="dashboard-columns">
      <section className="panel">
        <div className="panel-heading"><h3>System attention</h3><span>Current compliance exceptions</span></div>
        <div className="big-status"><div className={(personnelIssues + fleetCritical) > 0 ? 'status-icon warning' : 'status-icon success'}>{(personnelIssues + fleetCritical) > 0 ? <AlertIcon/> : <CheckIcon/>}</div><div><strong>{personnelIssues + fleetCritical}</strong><span>high-priority compliance exceptions</span></div></div>
        <div className="mini-row"><span>Open fleet deficiencies</span><strong>{openDeficiencies.count ?? 0}</strong></div>
        <div className="mini-row"><span>Critical open deficiencies</span><strong>{criticalDeficiencies.count ?? 0}</strong></div>
      </section>
      <section className="panel">
        <div className="panel-heading"><h3>Environment</h3><span>Live application foundation</span></div>
        <div className="environment-list"><div><span>Production URL</span><strong>portal.geaemss.org</strong></div><div><span>Database</span><strong>Supabase PostgreSQL</strong></div><div><span>Authentication</span><strong className="ok-dot">Connected</strong></div><div><span>Authorization</span><strong>Row Level Security</strong></div></div>
      </section>
    </div>
  </>
}
