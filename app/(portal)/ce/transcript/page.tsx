import type { Metadata } from 'next'
import Link from 'next/link'
import { PageHeader } from '@/components/page-header'
import { CEExportButtons } from '@/components/ce-export-buttons'
import { getCEContext } from '@/lib/ce-auth'
import { formatInTimeZone } from '@/lib/time-zone'

export const metadata: Metadata = { title: 'My CE Transcript' }
function one<T = any>(value: T | T[] | null | undefined): T | null { return Array.isArray(value) ? (value[0] ?? null) : (value ?? null) }

export default async function CETranscriptPage() {
  const { supabase, providerId } = await getCEContext()
  if (!providerId) return <><PageHeader title="My CE Transcript" description="A linked provider record is required."/><div className="empty-state"><strong>No linked provider record</strong></div></>

  const [{ data: attendance, error: attendanceError }, { data: external, error: externalError }] = await Promise.all([
    supabase.from('ce_attendance').select('id, status, verified_at, credit_hours_awarded, verification_method, ce_sessions(start_at, timezone, location_name, ce_courses(title, course_code, category))').eq('provider_id', providerId).eq('status','completed').order('verified_at', { ascending:false }).limit(5000),
    supabase.from('ce_external_submissions').select('id, title, sponsor, category, completion_date, credit_hours, status, reviewed_at').eq('provider_id', providerId).eq('status','approved').order('completion_date', { ascending:false }).limit(5000),
  ])

  const rows:any[] = []
  for (const item of attendance ?? []) {
    const session = one<any>(item.ce_sessions)
    const course = one<any>(session?.ce_courses)
    rows.push({
      date: session?.start_at ? new Date(session.start_at).toISOString().slice(0,10) : '',
      title: course?.title || 'GEAEMS CE Session',
      sponsor: 'GEAEMS',
      category: course?.category || '',
      source: 'Instructor-led',
      location: session?.location_name || '',
      hours: Number(item.credit_hours_awarded || 0),
      detail: item.verified_at ? `Verified ${formatInTimeZone(item.verified_at, session?.timezone || 'America/Chicago')}` : '',
    })
  }
  for (const item of external ?? []) rows.push({ date:item.completion_date, title:item.title, sponsor:item.sponsor || '', category:item.category || '', source:'External / online', location:'', hours:Number(item.credit_hours || 0), detail:'Certificate approved' })
  rows.sort((a,b) => String(b.date).localeCompare(String(a.date)))
  const total = rows.reduce((sum,row) => sum + Number(row.hours || 0), 0)
  const byCategory = new Map<string,number>()
  for (const row of rows) byCategory.set(row.category || 'Uncategorized', (byCategory.get(row.category || 'Uncategorized') || 0) + Number(row.hours || 0))

  return <>
    <PageHeader eyebrow="CE Tracking" title="My CE Transcript" description="Approved continuing education from GEAEMS sessions and external certificate submissions." action={<div className="header-actions"><Link className="secondary-button button-link" href="/ce">Back to CE</Link><Link className="secondary-button button-link" href="/ce/external/new">Upload external CE</Link></div>} />
    {(attendanceError || externalError) && <div className="banner danger"><div><strong>Transcript may be incomplete</strong><span>{attendanceError?.message || externalError?.message}</span></div></div>}
    <div className="summary-strip"><div><span>Total CE</span><strong>{total.toFixed(2)}</strong><small>hours</small></div><div><span>Completed records</span><strong>{rows.length}</strong><small>approved transcript entries</small></div>{[...byCategory.entries()].slice(0,2).map(([category,hours]) => <div key={category}><span>{category}</span><strong>{hours.toFixed(2)}</strong><small>hours</small></div>)}</div>

    <section className="report-section">
      <div className="section-heading"><div><span>Transcript</span><h2>Completed continuing education</h2><p>Only verified GEAEMS attendance and approved external CE appear on the transcript.</p></div><CEExportButtons rows={rows} filename="GEAEMS-CE-Transcript" columns={[{key:'date',label:'Completion Date'},{key:'title',label:'Course / Training'},{key:'sponsor',label:'Sponsor'},{key:'category',label:'Category'},{key:'source',label:'Source'},{key:'location',label:'Location'},{key:'hours',label:'CE Hours'},{key:'detail',label:'Verification'}]} /></div>
      {rows.length === 0 ? <div className="empty-state"><strong>No completed CE on your transcript yet</strong><span>Verified session attendance and approved external CE will appear here.</span></div> : <div className="table-card"><table><thead><tr><th>Date</th><th>Course / training</th><th>Category</th><th>Source</th><th>Hours</th><th>Verification</th></tr></thead><tbody>{rows.map((row,index) => <tr key={`${row.source}-${row.date}-${index}`}><td>{row.date}</td><td><strong>{row.title}</strong><div className="muted-code">{[row.sponsor,row.location].filter(Boolean).join(' · ')}</div></td><td>{row.category || '—'}</td><td>{row.source}</td><td>{Number(row.hours).toFixed(2)}</td><td>{row.detail}</td></tr>)}</tbody></table></div>}
    </section>
  </>
}
