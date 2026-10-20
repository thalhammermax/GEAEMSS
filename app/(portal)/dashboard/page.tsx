import type { Metadata } from 'next'
import Link from 'next/link'
import { createClient } from '@/lib/supabase/server'
import { PageHeader } from '@/components/page-header'
import { StatCard } from '@/components/stat-card'
import { AlertIcon, CheckIcon } from '@/components/icons'
import { enabledModuleKeys, moduleLabel } from '@/lib/modules'
import { requireSession } from '@/lib/session'

export const metadata: Metadata = { title: 'Dashboard' }

export default async function DashboardPage() {
  const supabase = await createClient()
  const session = await requireSession()
  const moduleStates = session.modules

  // One round trip: every count is computed inside Postgres through the
  // caller's row-level security (see migration 023, dashboard_summary()).
  const { data: summary, error } = await supabase.rpc('dashboard_summary')
  const firstError = error
  const n = (key: string) => Number(summary?.[key] ?? 0)

  const personnelEnabled = moduleStates.personnel
  const credentialsEnabled = moduleStates.credentials
  const fleetEnabled = moduleStates.fleet
  const inspectionsEnabled = moduleStates.inspections
  const narcoticsEnabled = moduleStates.narcotics

  const providers = { count: n('providers') }
  const agencies = { count: n('agencies') }
  const vehicles = { count: n('vehicles') }
  const pending = { count: n('pending_submissions') }
  const expiredCredentials = { count: n('credentials_expired') }
  const expiringCredentials = { count: n('credentials_expiring') }
  const missingCredentials = { count: n('credentials_missing') }
  const overdueInspections = { count: n('inspections_overdue') }
  const dueInspections = { count: n('inspections_due_soon') }
  const failedInspections = { count: n('inspections_failed') }
  const missingInspections = { count: n('inspections_missing') }
  const expiringVehicleLicenses = { count: n('licenses_expiring') }
  const expiredVehicleLicenses = { count: n('licenses_expired') }
  const missingVehicleLicenses = { count: n('licenses_missing') }
  const openDeficiencyCount = n('deficiencies_open')
  const criticalDeficiencyCount = n('deficiencies_critical')
  const missingNarcotics: Array<{ vehicle_id: string; agency: string; unit: string; state: string }> = narcoticsEnabled ? (summary?.narcotics_missing ?? []) : []

  const personnelIssues = credentialsEnabled ? expiredCredentials.count + missingCredentials.count : 0
  const fleetCritical = fleetEnabled
    ? (inspectionsEnabled ? overdueInspections.count + failedInspections.count : 0)
      + expiredVehicleLicenses.count
      + missingVehicleLicenses.count
    : 0
  const enabledNames = enabledModuleKeys(moduleStates).map(moduleLabel)

  return <>
    <PageHeader title="System Dashboard" description="Live status for the GEAEMS Portal modules currently enabled for production." />
    {firstError && <div className="banner danger"><AlertIcon/><div><strong>Some dashboard data could not be loaded.</strong><span>{firstError.message}</span></div></div>}

    {narcoticsEnabled && missingNarcotics.length > 0 && <div className="banner danger narcotics-dashboard-alert"><AlertIcon/><div><strong>{missingNarcotics.length} daily narcotics count{missingNarcotics.length === 1 ? '' : 's'} incomplete</strong><span>{missingNarcotics.slice(0, 12).map((row) => `${row.agency} ${row.unit} — ${row.state}`).join(' • ')}{missingNarcotics.length > 12 ? ` • +${missingNarcotics.length - 12} more` : ''}</span><Link href="/narcotics">Open Narcotics Management →</Link></div></div>}

    {personnelEnabled && <section className="section-block">
      <div className="section-title"><div><span>Personnel</span><h2>{credentialsEnabled ? 'Provider & credential readiness' : 'Provider records'}</h2></div><span className="section-badge">{providers.count ?? 0} providers · {agencies.count ?? 0} agencies</span></div>
      <div className="stat-grid">
        <StatCard label="Providers" value={providers.count ?? 0} detail="System personnel records" />
        {credentialsEnabled && <StatCard label="Expired requirements" value={expiredCredentials.count ?? 0} tone={(expiredCredentials.count ?? 0) > 0 ? 'danger' : 'success'} detail="Required credentials past expiration" />}
        {credentialsEnabled && <StatCard label="Expiring soon" value={expiringCredentials.count ?? 0} tone={(expiringCredentials.count ?? 0) > 0 ? 'warning' : 'default'} detail="Within configured warning window" />}
        {credentialsEnabled && <StatCard label="Missing requirements" value={missingCredentials.count ?? 0} tone={(missingCredentials.count ?? 0) > 0 ? 'danger' : 'success'} detail="No verified current credential" />}
        {credentialsEnabled && <StatCard label="Pending verification" value={pending.count ?? 0} tone={(pending.count ?? 0) > 0 ? 'warning' : 'default'} detail="Provider renewal submissions" />}
      </div>
    </section>}

    {fleetEnabled && <section className="section-block">
      <div className="section-title"><div><span>Fleet</span><h2>{inspectionsEnabled ? 'Vehicle & inspection compliance' : 'Vehicle compliance'}</h2></div><span className="section-badge">{vehicles.count ?? 0} active vehicles</span></div>
      <div className="stat-grid">
        <StatCard label="Active vehicles" value={vehicles.count ?? 0} detail="Across visible agencies" />
        {inspectionsEnabled && <StatCard label="Inspections overdue" value={overdueInspections.count ?? 0} tone={(overdueInspections.count ?? 0) > 0 ? 'danger' : 'success'} detail="Past required due date" />}
        {inspectionsEnabled && <StatCard label="Inspections due soon" value={dueInspections.count ?? 0} tone={(dueInspections.count ?? 0) > 0 ? 'warning' : 'default'} detail="Within configured warning window" />}
        {inspectionsEnabled && <StatCard label="Failed / OOS inspections" value={failedInspections.count ?? 0} tone={(failedInspections.count ?? 0) > 0 ? 'danger' : 'success'} detail="Most recent required inspection" />}
        {inspectionsEnabled && <StatCard label="Missing inspections" value={missingInspections.count ?? 0} tone={(missingInspections.count ?? 0) > 0 ? 'danger' : 'success'} detail="Required inspection or schedule missing" />}
        <StatCard label="Licenses expiring soon" value={expiringVehicleLicenses.count ?? 0} tone={(expiringVehicleLicenses.count ?? 0) > 0 ? 'warning' : 'default'} detail="Within configured warning window" />
        <StatCard label="Expired vehicle licenses" value={expiredVehicleLicenses.count ?? 0} tone={(expiredVehicleLicenses.count ?? 0) > 0 ? 'danger' : 'success'} detail="Required current licenses" />
        <StatCard label="Missing vehicle licenses" value={missingVehicleLicenses.count ?? 0} tone={(missingVehicleLicenses.count ?? 0) > 0 ? 'danger' : 'success'} detail="Required license record missing" />
      </div>
    </section>}

    {!personnelEnabled && !fleetEnabled && <div className="empty-state"><strong>No operational data modules are enabled.</strong><span>Use Administration → Module Controls to enable a production module.</span></div>}

    <div className="dashboard-columns">
      <section className="panel">
        <div className="panel-heading"><h3>System attention</h3><span>Enabled-module compliance exceptions</span></div>
        <div className="big-status"><div className={(personnelIssues + fleetCritical) > 0 ? 'status-icon warning' : 'status-icon success'}>{(personnelIssues + fleetCritical) > 0 ? <AlertIcon/> : <CheckIcon/>}</div><div><strong>{personnelIssues + fleetCritical}</strong><span>high-priority compliance exceptions</span></div></div>
        {inspectionsEnabled && <><div className="mini-row"><span>Open fleet deficiencies</span><strong>{openDeficiencyCount}</strong></div><div className="mini-row"><span>Critical open deficiencies</span><strong>{criticalDeficiencyCount}</strong></div></>}
      </section>
      <section className="panel">
        <div className="panel-heading"><h3>Environment</h3><span>Live application foundation</span></div>
        <div className="environment-list"><div><span>Production URL</span><strong>portal.geaemss.org</strong></div><div><span>Enabled modules</span><strong>{enabledNames.join(', ') || 'None'}</strong></div><div><span>Database</span><strong>Supabase PostgreSQL</strong></div><div><span>Authentication</span><strong className="ok-dot">Connected</strong></div><div><span>Authorization</span><strong>Row Level Security</strong></div></div>
      </section>
    </div>
  </>
}
