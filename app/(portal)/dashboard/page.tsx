import type { Metadata } from 'next'
import Link from 'next/link'
import { createClient } from '@/lib/supabase/server'
import { PageHeader } from '@/components/page-header'
import { StatCard } from '@/components/stat-card'
import { AlertIcon, CheckIcon } from '@/components/icons'
import { dateInTimeZone, relationOne } from '@/lib/narcotics'
import { enabledModuleKeys, getModuleStates, moduleLabel } from '@/lib/modules'

export const metadata: Metadata = { title: 'Dashboard' }

const emptyResult = () => Promise.resolve({ data: [] as any[], count: 0, error: null } as any)

export default async function DashboardPage() {
  const supabase = await createClient()
  const moduleStates = await getModuleStates(supabase)

  const personnelEnabled = moduleStates.personnel
  const credentialsEnabled = moduleStates.credentials
  const fleetEnabled = moduleStates.fleet
  const inspectionsEnabled = moduleStates.inspections
  const narcoticsEnabled = moduleStates.narcotics

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
    narcoticsSettings,
    narcoticsVehicles,
  ] = await Promise.all([
    personnelEnabled ? supabase.from('providers').select('*', { count: 'exact', head: true }) : emptyResult(),
    supabase.from('agencies').select('*', { count: 'exact', head: true }).eq('active', true),
    fleetEnabled ? supabase.from('vehicles').select('*', { count: 'exact', head: true }).eq('active', true) : emptyResult(),
    credentialsEnabled ? supabase.from('credential_submissions').select('*', { count: 'exact', head: true }).eq('status', 'pending') : emptyResult(),
    credentialsEnabled ? supabase.from('provider_compliance').select('*', { count: 'exact', head: true }).eq('compliance_status', 'EXPIRED') : emptyResult(),
    credentialsEnabled ? supabase.from('provider_compliance').select('*', { count: 'exact', head: true }).eq('compliance_status', 'EXPIRING_SOON') : emptyResult(),
    credentialsEnabled ? supabase.from('provider_compliance').select('*', { count: 'exact', head: true }).eq('compliance_status', 'MISSING') : emptyResult(),
    inspectionsEnabled ? supabase.from('vehicle_inspection_compliance').select('*', { count: 'exact', head: true }).eq('compliance_status', 'OVERDUE') : emptyResult(),
    inspectionsEnabled ? supabase.from('vehicle_inspection_compliance').select('*', { count: 'exact', head: true }).eq('compliance_status', 'DUE_SOON') : emptyResult(),
    inspectionsEnabled ? supabase.from('vehicle_inspection_compliance').select('*', { count: 'exact', head: true }).eq('compliance_status', 'FAILED') : emptyResult(),
    inspectionsEnabled ? supabase.from('vehicle_inspection_compliance').select('*', { count: 'exact', head: true }).in('compliance_status', ['MISSING', 'SCHEDULE_MISSING']) : emptyResult(),
    inspectionsEnabled ? supabase.from('vehicle_inspection_deficiencies').select('*', { count: 'exact', head: true }).eq('status', 'open') : emptyResult(),
    inspectionsEnabled ? supabase.from('vehicle_inspection_deficiencies').select('*', { count: 'exact', head: true }).eq('status', 'open').eq('severity', 'critical') : emptyResult(),
    fleetEnabled ? supabase.from('vehicle_license_compliance').select('*', { count: 'exact', head: true }).eq('compliance_status', 'EXPIRING_SOON') : emptyResult(),
    fleetEnabled ? supabase.from('vehicle_license_compliance').select('*', { count: 'exact', head: true }).eq('compliance_status', 'EXPIRED') : emptyResult(),
    fleetEnabled ? supabase.from('vehicle_license_compliance').select('*', { count: 'exact', head: true }).eq('compliance_status', 'MISSING') : emptyResult(),
    narcoticsEnabled ? supabase.from('narcotics_agency_settings').select('agency_id, enabled, timezone') : emptyResult(),
    narcoticsEnabled ? supabase.from('vehicles').select('id, agency_id, unit_number, fleet_number, narcotics_count_required, agencies(name, short_name), vehicle_types(name, narcotics_template_id)').eq('active', true).eq('narcotics_count_required', true).order('unit_number') : emptyResult(),
  ])

  const narcoticsSettingMap = new Map((narcoticsSettings.data ?? []).map((setting: any) => [setting.agency_id, setting]))
  const narcoticsRows = narcoticsEnabled
    ? (narcoticsVehicles.data ?? []).map((vehicle: any) => {
        const setting: any = narcoticsSettingMap.get(vehicle.agency_id)
        const agency = relationOne<any>(vehicle.agencies)
        const type = relationOne<any>(vehicle.vehicle_types)
        return { ...vehicle, agency, type, localDate: dateInTimeZone(setting?.timezone || 'America/Chicago'), enabled: setting?.enabled !== false }
      }).filter((row: any) => row.enabled)
    : []

  const narcoticsDates = [...new Set(narcoticsRows.map((row: any) => row.localDate))]
  const narcoticsVehicleIds = narcoticsRows.map((row: any) => row.id)
  const narcoticsCounts = narcoticsEnabled && narcoticsVehicleIds.length && narcoticsDates.length
    ? await supabase.from('narcotics_counts').select('vehicle_id, count_date, status').in('vehicle_id', narcoticsVehicleIds).in('count_date', narcoticsDates)
    : { data: [] as any[], error: null }

  const submittedNarcotics = new Set((narcoticsCounts.data ?? []).filter((count: any) => count.status === 'submitted').map((count: any) => `${count.vehicle_id}|${count.count_date}`))
  const draftNarcotics = new Set((narcoticsCounts.data ?? []).filter((count: any) => count.status === 'draft').map((count: any) => `${count.vehicle_id}|${count.count_date}`))
  const missingNarcotics = narcoticsRows.filter((row: any) => !submittedNarcotics.has(`${row.id}|${row.localDate}`))

  const results = [
    providers, agencies, vehicles, pending, expiredCredentials, expiringCredentials, missingCredentials,
    overdueInspections, dueInspections, failedInspections, missingInspections, openDeficiencies,
    criticalDeficiencies, expiringVehicleLicenses, expiredVehicleLicenses, missingVehicleLicenses,
    narcoticsSettings, narcoticsVehicles, narcoticsCounts,
  ]
  const firstError = results.find((result) => result.error)?.error

  const personnelIssues = credentialsEnabled ? (expiredCredentials.count ?? 0) + (missingCredentials.count ?? 0) : 0
  const fleetCritical = fleetEnabled
    ? (inspectionsEnabled ? (overdueInspections.count ?? 0) + (failedInspections.count ?? 0) : 0)
      + (expiredVehicleLicenses.count ?? 0)
      + (missingVehicleLicenses.count ?? 0)
    : 0
  const enabledNames = enabledModuleKeys(moduleStates).map(moduleLabel)

  return <>
    <PageHeader title="System Dashboard" description="Live status for the GEAEMS Portal modules currently enabled for production." />
    {firstError && <div className="banner danger"><AlertIcon/><div><strong>Some dashboard data could not be loaded.</strong><span>{firstError.message}</span></div></div>}

    {narcoticsEnabled && missingNarcotics.length > 0 && <div className="banner danger narcotics-dashboard-alert"><AlertIcon/><div><strong>{missingNarcotics.length} daily narcotics count{missingNarcotics.length === 1 ? '' : 's'} incomplete</strong><span>{missingNarcotics.slice(0, 12).map((row: any) => `${row.agency?.short_name || row.agency?.name || 'Agency'} ${row.unit_number || row.fleet_number || 'Unnumbered'} — ${!row.type?.narcotics_template_id ? 'no form configured' : draftNarcotics.has(`${row.id}|${row.localDate}`) ? 'draft not submitted' : 'not started'}`).join(' • ')}{missingNarcotics.length > 12 ? ` • +${missingNarcotics.length - 12} more` : ''}</span><Link href="/narcotics">Open Narcotics Management →</Link></div></div>}

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
        {inspectionsEnabled && <><div className="mini-row"><span>Open fleet deficiencies</span><strong>{openDeficiencies.count ?? 0}</strong></div><div className="mini-row"><span>Critical open deficiencies</span><strong>{criticalDeficiencies.count ?? 0}</strong></div></>}
      </section>
      <section className="panel">
        <div className="panel-heading"><h3>Environment</h3><span>Live application foundation</span></div>
        <div className="environment-list"><div><span>Production URL</span><strong>portal.geaemss.org</strong></div><div><span>Enabled modules</span><strong>{enabledNames.join(', ') || 'None'}</strong></div><div><span>Database</span><strong>Supabase PostgreSQL</strong></div><div><span>Authentication</span><strong className="ok-dot">Connected</strong></div><div><span>Authorization</span><strong>Row Level Security</strong></div></div>
      </section>
    </div>
  </>
}
