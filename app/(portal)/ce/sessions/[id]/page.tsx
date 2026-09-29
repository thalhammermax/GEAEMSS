import type { Metadata } from 'next'
import Link from 'next/link'
import { notFound } from 'next/navigation'
import { PageHeader } from '@/components/page-header'
import { CEExportButtons } from '@/components/ce-export-buttons'
import { requireCESessionManagerPage } from '@/lib/ce-auth'
import { dateTimeLocalValue, formatInTimeZone } from '@/lib/time-zone'
import { assignCEInstructor, generateCEVerificationCode, manualCEAttendance, removeCEInstructor, updateCESession } from '../../actions'

export const metadata: Metadata = { title: 'CE Session Roster' }
type Props = { params: Promise<{ id: string }>; searchParams: Promise<{ notice?: string; error?: string }> }
function one<T = any>(value: T | T[] | null | undefined): T | null { return Array.isArray(value) ? (value[0] ?? null) : (value ?? null) }

export default async function CESessionPage({ params, searchParams }: Props) {
  const { id } = await params
  const qs = await searchParams
  const context = await requireCESessionManagerPage(id)
  const { supabase, canManageCE } = context

  const [{ data: session, error }, { data: attendance }, { data: secret }, { data: providerDirectory }, { data: assignments }] = await Promise.all([
    supabase.from('ce_sessions').select('id, course_id, start_at, end_at, timezone, location_name, location_address, capacity, credit_hours_override, self_checkin_enabled, check_in_open_minutes, verification_close_hours, verification_code_generated_at, status, notes, ce_courses(id, title, course_code, category, credit_hours)').eq('id', id).maybeSingle(),
    supabase.from('ce_attendance').select('id, provider_id, status, source, checked_in_at, verified_at, verification_method, credit_hours_awarded, notes, created_at').eq('session_id', id).order('checked_in_at'),
    supabase.from('ce_session_secrets').select('verification_code, generated_at').eq('session_id', id).maybeSingle(),
    supabase.rpc('ce_provider_directory', { p_session_id: id }),
    supabase.from('ce_session_instructors').select('user_id, created_at').eq('session_id', id),
  ])
  if (error) throw error
  if (!session) notFound()
  const course = one<any>(session.ce_courses)
  const providerMap = new Map((providerDirectory ?? []).map((p:any) => [p.provider_id, p]))
  const roster = (attendance ?? []).map((row:any) => ({ ...row, provider: providerMap.get(row.provider_id) }))
  const completed = roster.filter((row:any) => row.status === 'completed').length
  const checkedIn = roster.filter((row:any) => row.status === 'checked_in').length
  const rosterExport = roster.map((row:any) => ({
    provider_name: row.provider?.provider_name || row.provider_id,
    provider_number: row.provider?.provider_number || '',
    agency: row.provider?.agency_name || '',
    status: row.status,
    checked_in_at: row.checked_in_at ? formatInTimeZone(row.checked_in_at, session.timezone) : '',
    verified_at: row.verified_at ? formatInTimeZone(row.verified_at, session.timezone) : '',
    verification_method: row.verification_method || '',
    source: row.source,
    credit_hours: row.credit_hours_awarded ?? '',
    notes: row.notes || '',
  }))

  let instructors: any[] = []
  if (canManageCE) {
    const { data } = await supabase.rpc('ce_instructor_directory')
    instructors = data ?? []
  }
  const instructorMap = new Map(instructors.map((row:any) => [row.user_id, row]))
  const assignedIds = new Set((assignments ?? []).map((row:any) => row.user_id))
  const availableInstructors = instructors.filter((row:any) => !assignedIds.has(row.user_id))
  const filename = `${course?.title || 'CE'}-${new Date(session.start_at).toISOString().slice(0,10)}-roster`.replace(/[^a-zA-Z0-9._-]+/g, '-')

  return <>
    <PageHeader eyebrow="CE Session" title={course?.title || 'CE Session'} description={`${formatInTimeZone(session.start_at, session.timezone)} · ${session.location_name || 'Location TBD'}`} action={<div className="header-actions"><Link className="secondary-button button-link" href="/ce">CE dashboard</Link>{canManageCE && <Link className="secondary-button button-link" href={`/ce/courses/${session.course_id}`}>Class schedule</Link>}</div>} />
    {qs.notice && <div className="banner success"><div><strong>Session updated</strong><span>{qs.notice}</span></div></div>}
    {qs.error && <div className="banner danger"><div><strong>Session action failed</strong><span>{qs.error}</span></div></div>}

    <div className="summary-strip"><div><span>Roster</span><strong>{roster.length}</strong><small>providers</small></div><div><span>Completed</span><strong>{completed}</strong><small>verified attendance</small></div><div><span>Checked in</span><strong>{checkedIn}</strong><small>awaiting completion</small></div><div><span>CE hours</span><strong>{Number(session.credit_hours_override ?? course?.credit_hours ?? 0).toFixed(2)}</strong><small>per completion</small></div></div>

    <div className="profile-grid print-hide">
      <section className="form-card compact-card">
        <div className="form-card-heading"><div><span>Attendance verification</span><h2>End-of-session code</h2></div>{secret?.verification_code && <span className="pill green">Released</span>}</div>
        {secret?.verification_code ? <><div className="empty-state compact"><span>Give this random code to attendees at the end of this session.</span><strong style={{fontSize:'32px', letterSpacing:'0.18em'}}>{secret.verification_code}</strong><span>Released {formatInTimeZone(secret.generated_at, session.timezone)}</span></div></> : <div className="empty-state compact"><strong>No completion code released yet</strong><span>Generate the code at the end of class. Providers must have checked in before they can use it.</span><form action={generateCEVerificationCode}><input type="hidden" name="session_id" value={id}/><button className="primary-button" type="submit">Generate & release code</button></form></div>}
      </section>

      <section className="form-card compact-card">
        <div className="form-card-heading"><div><span>Paper / corrected roster</span><h2>Manual attendance entry</h2></div></div>
        <form action={manualCEAttendance}>
          <input type="hidden" name="session_id" value={id}/>
          <div className="form-grid">
            <label className="field span-full"><span>Provider</span><select name="provider_id" required defaultValue=""><option value="" disabled>Select provider…</option>{(providerDirectory ?? []).map((p:any) => <option key={p.provider_id} value={p.provider_id}>{p.provider_name}{p.provider_number ? ` · ${p.provider_number}` : ''}{p.agency_name ? ` · ${p.agency_name}` : ''}</option>)}</select></label>
            <label className="field span-full"><span>Roster note</span><input name="notes" placeholder="Optional paper roster / correction note" /></label>
            <label className="checkbox-row span-full"><input type="checkbox" name="completed" defaultChecked />Mark provider as completed and award CE credit</label>
          </div>
          <div className="form-actions"><button className="primary-button" type="submit">Add / update roster entry</button></div>
        </form>
      </section>
    </div>

    <section className="report-section">
      <div className="section-heading"><div><span>Attendance roster</span><h2>Session roster</h2><p>Electronic check-ins and manually entered paper-roster records appear together. Completion status is the authoritative attendance record.</p></div><CEExportButtons rows={rosterExport} filename={filename} columns={[{key:'provider_name',label:'Provider'},{key:'provider_number',label:'System ID'},{key:'agency',label:'Agency'},{key:'status',label:'Status'},{key:'checked_in_at',label:'Checked In'},{key:'verified_at',label:'Verified'},{key:'verification_method',label:'Verification Method'},{key:'source',label:'Entry Source'},{key:'credit_hours',label:'CE Hours'},{key:'notes',label:'Notes'}]} /></div>
      {roster.length === 0 ? <div className="empty-state compact"><strong>No attendance recorded yet</strong><span>Electronic check-ins and manual roster entries will appear here.</span></div> : <div className="table-card"><table><thead><tr><th>Provider</th><th>Agency</th><th>Checked in</th><th>Verified</th><th>Status</th><th>Method</th><th>Hours</th></tr></thead><tbody>{roster.map((row:any) => <tr key={row.id}><td><strong>{row.provider?.provider_name || row.provider_id}</strong><div className="muted-code">{row.provider?.provider_number || 'No System ID'}</div></td><td>{row.provider?.agency_name || '—'}</td><td>{row.checked_in_at ? formatInTimeZone(row.checked_in_at, session.timezone) : '—'}</td><td>{row.verified_at ? formatInTimeZone(row.verified_at, session.timezone) : '—'}</td><td><span className={`pill ${row.status === 'completed' ? 'green' : row.status === 'absent' ? 'red' : 'amber'}`}>{row.status}</span></td><td>{row.verification_method || row.source}</td><td>{row.credit_hours_awarded == null ? '—' : Number(row.credit_hours_awarded).toFixed(2)}</td></tr>)}</tbody></table></div>}
    </section>

    {canManageCE && <section className="form-card print-hide">
      <div className="form-card-heading"><div><span>Instructor access</span><h2>Assigned CE instructors</h2></div></div>
      {(assignments ?? []).length === 0 ? <p className="panel-copy">No CE instructors are assigned. CE Coordinators and System Administrators can still manage this session.</p> : <div className="agency-permission-list">{(assignments ?? []).map((assignment:any) => <div className="agency-permission-row" key={assignment.user_id}><div className="agency-access-name"><span><strong>{instructorMap.get(assignment.user_id)?.display_name || assignment.user_id}</strong><small>CE Instructor</small></span></div><form action={removeCEInstructor}><input type="hidden" name="session_id" value={id}/><input type="hidden" name="user_id" value={assignment.user_id}/><button className="secondary-button small danger-outline" type="submit">Remove</button></form></div>)}</div>}
      {availableInstructors.length > 0 && <form action={assignCEInstructor} className="inline-form"><input type="hidden" name="session_id" value={id}/><select name="user_id" required defaultValue=""><option value="" disabled>Assign a CE Instructor…</option>{availableInstructors.map((row:any) => <option key={row.user_id} value={row.user_id}>{row.display_name}</option>)}</select><button className="secondary-button" type="submit">Assign instructor</button></form>}
      {instructors.length === 0 && <p className="panel-copy">Assign the CE Instructor role to portal users from Administration → Users before assigning them to sessions.</p>}
    </section>}

    {canManageCE && <section className="form-card print-hide">
      <form action={updateCESession}>
        <input type="hidden" name="session_id" value={id}/>
        <div className="form-card-heading"><div><span>Session settings</span><h2>Edit date, location & attendance rules</h2></div></div>
        <div className="form-grid">
          <label className="field"><span>Starts</span><input type="datetime-local" name="start_at" defaultValue={dateTimeLocalValue(session.start_at, session.timezone)} required /></label>
          <label className="field"><span>Ends</span><input type="datetime-local" name="end_at" defaultValue={dateTimeLocalValue(session.end_at, session.timezone)} required /></label>
          <label className="field"><span>Time zone</span><select name="timezone" defaultValue={session.timezone}><option value="America/Chicago">Central Time</option><option value="America/New_York">Eastern Time</option><option value="America/Denver">Mountain Time</option><option value="America/Los_Angeles">Pacific Time</option></select></label>
          <label className="field"><span>Status</span><select name="status" defaultValue={session.status}><option value="scheduled">Scheduled</option><option value="completed">Completed</option><option value="cancelled">Cancelled</option></select></label>
          <label className="field"><span>Location name</span><input name="location_name" defaultValue={session.location_name || ''}/></label>
          <label className="field"><span>Capacity</span><input type="number" min="1" name="capacity" defaultValue={session.capacity || ''}/></label>
          <label className="field span-full"><span>Location address / room / link</span><input name="location_address" defaultValue={session.location_address || ''}/></label>
          <label className="field"><span>Override CE hours</span><input type="number" min="0" step="0.25" name="credit_hours_override" defaultValue={session.credit_hours_override ?? ''}/></label>
          <label className="field"><span>Check-in opens (minutes before start)</span><input type="number" min="0" max="1440" name="check_in_open_minutes" defaultValue={session.check_in_open_minutes}/></label>
          <label className="field"><span>Completion code valid (hours after class)</span><input type="number" min="1" max="168" name="verification_close_hours" defaultValue={session.verification_close_hours}/></label>
          <label className="checkbox-row span-full"><input type="checkbox" name="self_checkin_enabled" defaultChecked={session.self_checkin_enabled}/>Allow provider self check-in</label>
          <label className="field span-full"><span>Session notes</span><textarea name="notes" rows={3} defaultValue={session.notes || ''}/></label>
        </div>
        <div className="form-actions"><button className="primary-button" type="submit">Save session settings</button></div>
      </form>
    </section>}
  </>
}
