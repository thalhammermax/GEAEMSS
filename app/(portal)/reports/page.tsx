import type { Metadata } from 'next'
import { PageHeader } from '@/components/page-header'

export const metadata: Metadata = { title: 'Reports' }
const reports = ['System Personnel Roster','Agency Personnel Roster','Credential Compliance','Credential Expiration','Missing Required Credentials','Fleet Roster','Vehicle License Expiration','Upcoming / Overdue Inspections','Open Inspection Deficiencies','Agency Compliance Summary']
export default function ReportsPage() { return <><PageHeader title="Reports" description="Operational and compliance reporting for system and agency administration." /><div className="report-grid">{reports.map((name) => <article className="report-card" key={name}><span>Report</span><strong>{name}</strong><p>Filtering and export controls will be added in the reporting phase.</p><button disabled>Open report</button></article>)}</div></> }
