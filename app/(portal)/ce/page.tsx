import type { Metadata } from 'next'
import Link from 'next/link'
import { PageHeader } from '@/components/page-header'
import { getCEContext } from '@/lib/ce-auth'
import { formatInTimeZone } from '@/lib/time-zone'
import { selfCheckInCE, verifyCEAttendance } from './actions'

export const metadata: Metadata = { title: 'CE Tracking' }
type Props = { searchParams: Promise<{ notice?: string; error?: string }> }

function one<T = any>(value: T | T[] | null | undefined): T | null {
  return Array.isArray(value) ? (value[0] ?? null) : (value ?? null)
}

export default async function CEPage({ searchParams }: Props) {
  const qs = await searchParams
  const { supabase, user, providerId, canManageCE, isCEInstructor } = await getCEContext()
  const from = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString()

  const sessionPromise = supabase
    .from('ce_sessions')
    .select('id, course_id, start_at, end_at, timezone, location_name, location_address, capacity, credit_hours_override, self_checkin_enabled, check_in_open_minutes, verification_code_generated_at, status, ce_courses(id, title, course_code, category, credit_hours, active)')
    .gte('end_at', from)
    .neq('status', 'cancelled')
    .order('start_at')
    .limit(100)

  const attendancePromise = providerId
    ? supabase.from('ce_attendance').select('id, session_id, status, checked_in_at, verified_at, verification_method, credit_hours_awarded').eq('provider_id', providerId).limit(5000)
    : Promise.resolve({ data: [] as any[], error: null })

  const assignmentPromise = isCEInstructor
    ? supabase.from('ce_session_instructors').select('session_id').eq('user_id', user.id)
    : Promise.resolve({ data: [] as any[], error: null })

  const externalPromise = providerId
    ? supabase.from('ce_external_submissions').select('id, title, completion_date, credit_hours, status, review_notes').eq('provider_id', providerId).order('submitted_at', { ascending: false }).limit(5000)
    : Promise.resolve({ data: [] as any[], error: null })

  const reviewCountPromise = canManageCE
    ? supabase.from('ce_external_submissions').select('id', { count: 'exact', head: true }).eq('status', 'pending')
    : Promise.resolve({ count: 0, error: null } as any)

  const [sessionsResult, attendanceResult, assignmentResult, externalResult, reviewCountResult] = await Promise.all([
    sessionPromise, attendancePromise, assignmentPromise, externalPromise, reviewCountPromise,
  ])

  const attendanceMap = new Map((attendanceResult.data ?? []).map((row: any) => [row.session_id, row]))
  const assigned = new Set((assignmentResult.data ?? []).map((row: any) => row.session_id))
  const sessions = (sessionsResult.data ?? []).filter((row: any) => one<any>(row.ce_courses)?.active !== false)
  const now = Date.now()

  const completedHours = [...attendanceMap.values()].filter((row: any) => row.status === 'completed').reduce((sum: number, row: any) => sum + Number(row.credit_hours_awarded || 0), 0)
  const approvedExternalHours = (externalResult.data ?? []).filter((row: any) => row.status === 'approved').reduce((sum: number, row: any) => sum + Number(row.credit_hours || 0), 0)

  const actions = <div className="header-actions">
    {providerId && <Link className="secondary-button button-link" href="/ce/transcript">My transcript</Link>}
    {providerId && <Link className="secondary-button button-link" href="/ce/external/new">Upload external CE</Link>}
    {canManageCE && <Link className="secondary-button button-link" href="/ce/courses">Manage classes</Link>}
    {canManageCE && <Link className="primary-button button-link" href="/ce/courses/new">New CE class</Link>}
  </div>

  return <>
    <PageHeader title="CE Tracking" description="Scheduled continuing education, attendance verification, electronic rosters, and external CE certificates." action={actions} />
    {qs.notice && <div className="banner success"><div><strong>CE updated</strong><span>{qs.notice}</span></div></div>}
    {qs.error && <div className="banner danger"><div><strong>CE action failed</strong><span>{qs.error}</span></div></div>}

    {providerId && <div className="summary-strip">
      <div><span>Instructor-led CE</span><strong>{completedHours.toFixed(2)}</strong><small>verified session hours</small></div>
      <div><span>Approved external CE</span><strong>{approvedExternalHours.toFixed(2)}</strong><small>hours from uploaded certificates</small></div>
      <div><span>Transcript total</span><strong>{(completedHours + approvedExternalHours).toFixed(2)}</strong><small>hours</small></div>
      <div><span>External review</span><strong>{(externalResult.data ?? []).filter((r:any) => r.status === 'pending').length}</strong><small>pending submission{(externalResult.data ?? []).filter((r:any) => r.status === 'pending').length === 1 ? '' : 's'}</small></div>
    </div>}

    {canManageCE && Number(reviewCountResult.count || 0) > 0 && <div className="banner warning"><div><strong>{reviewCountResult.count} external CE submission{reviewCountResult.count === 1 ? '' : 's'} awaiting review</strong><span>Online and outside-course certificates stay pending until a CE Coordinator approves them.</span></div><Link className="secondary-button button-link" href="/ce/external/review">Review submissions</Link></div>}

    <section className="report-section">
      <div className="section-heading"><div><span>Schedule</span><h2>Upcoming CE sessions</h2><p>Providers can self check in during the configured attendance window. At the end of class, the instructor releases a random completion code.</p></div></div>
      {sessionsResult.error ? <div className="empty-state danger-text"><strong>Unable to load CE sessions</strong><span>{sessionsResult.error.message}</span></div> : sessions.length === 0 ? <div className="empty-state"><strong>No upcoming CE sessions</strong><span>Scheduled classes will appear here.</span>{canManageCE && <Link className="primary-button button-link" href="/ce/courses/new">Create a CE class</Link>}</div> : <div className="table-card"><table>
        <thead><tr><th>Class</th><th>Date / time</th><th>Location</th><th>CE hours</th>{providerId && <th>Your attendance</th>}<th></th></tr></thead>
        <tbody>{sessions.map((session:any) => {
          const course = one<any>(session.ce_courses)
          const attendance:any = attendanceMap.get(session.id)
          const start = new Date(session.start_at).getTime()
          const end = new Date(session.end_at).getTime()
          const opens = start - Number(session.check_in_open_minutes || 60) * 60000
          const canCheckInNow = session.self_checkin_enabled && now >= opens && now <= end && !attendance
          const canManageSession = canManageCE || assigned.has(session.id)
          const hours = session.credit_hours_override ?? course?.credit_hours ?? 0
          return <tr key={session.id}>
            <td><strong>{course?.title || 'CE Class'}</strong><div className="muted-code">{[course?.course_code, course?.category].filter(Boolean).join(' · ') || 'GEAEMS CE'}</div></td>
            <td><strong>{formatInTimeZone(session.start_at, session.timezone || 'America/Chicago')}</strong><div className="muted-code">Ends {formatInTimeZone(session.end_at, session.timezone || 'America/Chicago')}</div></td>
            <td><strong>{session.location_name || 'Location TBD'}</strong>{session.location_address && <div className="muted-code">{session.location_address}</div>}</td>
            <td>{Number(hours).toFixed(2)}</td>
            {providerId && <td>{attendance?.status === 'completed' ? <span className="pill green">Completed</span> : attendance ? <div><span className="pill amber">Checked in</span>{session.verification_code_generated_at ? <form action={verifyCEAttendance} className="inline-form"><input type="hidden" name="session_id" value={session.id}/><input name="verification_code" required maxLength={12} placeholder="Completion code"/><button className="secondary-button small" type="submit">Verify</button></form> : <div className="muted-code">Waiting for instructor code</div>}</div> : canCheckInNow ? <form action={selfCheckInCE}><input type="hidden" name="session_id" value={session.id}/><button className="primary-button small" type="submit">Check in</button></form> : now < opens ? <span className="muted-code">Check-in opens {formatInTimeZone(new Date(opens), session.timezone || 'America/Chicago')}</span> : now <= end ? <span className="muted-code">Self check-in unavailable</span> : <span className="muted-code">Not checked in</span>}</td>}
            <td className="table-action">{canManageSession ? <Link href={`/ce/sessions/${session.id}`}>Manage roster</Link> : <span className="muted-code">—</span>}</td>
          </tr>
        })}</tbody>
      </table></div>}
    </section>

    {providerId && <section className="report-section">
      <div className="section-heading"><div><span>Online / outside training</span><h2>External CE certificates</h2><p>Use this for CE completed outside a GEAEMS electronic session, including online training such as mandated reporter education.</p></div><Link className="secondary-button button-link" href="/ce/external/new">Submit certificate</Link></div>
      {(externalResult.data ?? []).length === 0 ? <div className="empty-state compact"><strong>No external CE submitted</strong><span>Your online and outside-course certificates will appear here.</span></div> : <div className="table-card"><table><thead><tr><th>Training</th><th>Completed</th><th>Hours</th><th>Status</th><th>Review note</th></tr></thead><tbody>{(externalResult.data ?? []).slice(0, 10).map((row:any) => <tr key={row.id}><td><strong>{row.title}</strong></td><td>{row.completion_date}</td><td>{Number(row.credit_hours || 0).toFixed(2)}</td><td><span className={`pill ${row.status === 'approved' ? 'green' : row.status === 'rejected' ? 'red' : 'amber'}`}>{row.status === 'approved' ? 'Approved' : row.status === 'rejected' ? 'Rejected' : 'Pending review'}</span></td><td>{row.review_notes || '—'}</td></tr>)}</tbody></table></div>}
    </section>}
  </>
}
