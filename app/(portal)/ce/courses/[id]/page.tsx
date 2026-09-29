import type { Metadata } from 'next'
import Link from 'next/link'
import { notFound } from 'next/navigation'
import { PageHeader } from '@/components/page-header'
import { requireCEManagerPage } from '@/lib/ce-auth'
import { formatInTimeZone } from '@/lib/time-zone'
import { addCESession } from '../../actions'

export const metadata: Metadata = { title: 'CE Class Schedule' }
type Props = { params: Promise<{ id: string }>; searchParams: Promise<{ notice?: string; error?: string }> }

export default async function CECourseDetailPage({ params, searchParams }: Props) {
  const { id } = await params
  const qs = await searchParams
  const { supabase } = await requireCEManagerPage()
  const [{ data: course, error }, { data: sessions }] = await Promise.all([
    supabase.from('ce_courses').select('id, title, course_code, description, category, credit_hours, active').eq('id', id).maybeSingle(),
    supabase.from('ce_sessions').select('id, start_at, end_at, timezone, location_name, location_address, capacity, credit_hours_override, self_checkin_enabled, status, verification_code_generated_at').eq('course_id', id).order('start_at'),
  ])
  if (error) throw error
  if (!course) notFound()

  return <>
    <PageHeader eyebrow="CE Class" title={course.title} description={[course.course_code, course.category, `${Number(course.credit_hours || 0).toFixed(2)} CE hours`].filter(Boolean).join(' · ')} action={<div className="header-actions"><Link className="secondary-button button-link" href="/ce/courses">All classes</Link><Link className="secondary-button button-link" href="/ce">CE dashboard</Link></div>} />
    {qs.notice && <div className="banner success"><div><strong>Class updated</strong><span>{qs.notice}</span></div></div>}
    {qs.error && <div className="banner danger"><div><strong>Class action failed</strong><span>{qs.error}</span></div></div>}
    {course.description && <section className="panel"><div className="panel-heading"><h3>Class description</h3></div><p className="panel-copy">{course.description}</p></section>}

    <section className="report-section">
      <div className="section-heading"><div><span>Schedule</span><h2>Dates & locations</h2><p>Each row is a separate attendance roster and completion code. Providers can attend whichever offering applies to them.</p></div></div>
      {(sessions ?? []).length === 0 ? <div className="empty-state compact"><strong>No dates scheduled yet</strong><span>Add the first session below.</span></div> : <div className="table-card"><table><thead><tr><th>Date / time</th><th>Location</th><th>Hours</th><th>Self check-in</th><th>Status</th><th></th></tr></thead><tbody>{(sessions ?? []).map((session:any) => <tr key={session.id}><td><strong>{formatInTimeZone(session.start_at, session.timezone)}</strong><div className="muted-code">Ends {formatInTimeZone(session.end_at, session.timezone)}</div></td><td><strong>{session.location_name || 'TBD'}</strong>{session.location_address && <div className="muted-code">{session.location_address}</div>}</td><td>{Number(session.credit_hours_override ?? course.credit_hours ?? 0).toFixed(2)}</td><td>{session.self_checkin_enabled ? 'Enabled' : 'Manual only'}</td><td><span className={`pill ${session.status === 'scheduled' ? 'green' : session.status === 'cancelled' ? 'red' : 'gray'}`}>{session.status}</span></td><td className="table-action"><Link href={`/ce/sessions/${session.id}`}>Manage</Link></td></tr>)}</tbody></table></div>}
    </section>

    <section className="form-card">
      <form action={addCESession}>
        <input type="hidden" name="course_id" value={course.id} />
        <div className="form-card-heading"><div><span>Add offering</span><h2>Schedule another date / location</h2></div></div>
        <div className="form-grid">
          <label className="field"><span>Starts</span><input type="datetime-local" name="start_at" required /></label>
          <label className="field"><span>Ends</span><input type="datetime-local" name="end_at" required /></label>
          <label className="field"><span>Time zone</span><select name="timezone" defaultValue="America/Chicago"><option value="America/Chicago">Central Time</option><option value="America/New_York">Eastern Time</option><option value="America/Denver">Mountain Time</option><option value="America/Los_Angeles">Pacific Time</option></select></label>
          <label className="field"><span>Location name</span><input name="location_name" placeholder="Advocate Sherman Hospital, Elgin FD Station 1, Online, etc." /></label>
          <label className="field span-full"><span>Location address / room / link</span><input name="location_address" placeholder="Optional" /></label>
          <label className="field"><span>Capacity</span><input type="number" min="1" name="capacity" placeholder="Unlimited" /></label>
          <label className="field"><span>Override CE hours</span><input type="number" min="0" step="0.25" name="credit_hours_override" placeholder={`${Number(course.credit_hours || 0).toFixed(2)} default`} /></label>
          <label className="field"><span>Check-in opens (minutes before start)</span><input type="number" min="0" max="1440" name="check_in_open_minutes" defaultValue="60" /></label>
          <label className="field"><span>Completion code valid after class (hours)</span><input type="number" min="1" max="168" name="verification_close_hours" defaultValue="24" /></label>
          <label className="checkbox-row span-full"><input type="checkbox" name="self_checkin_enabled" defaultChecked />Allow providers to self check in electronically</label>
          <label className="field span-full"><span>Session notes</span><textarea name="notes" rows={3} placeholder="Parking, room instructions, instructor notes, etc." /></label>
        </div>
        <div className="form-actions"><button className="primary-button" type="submit">Add scheduled session</button></div>
      </form>
    </section>
  </>
}
