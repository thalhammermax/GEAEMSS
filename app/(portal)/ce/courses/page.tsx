import type { Metadata } from 'next'
import Link from 'next/link'
import { PageHeader } from '@/components/page-header'
import { requireCEManagerPage } from '@/lib/ce-auth'

export const metadata: Metadata = { title: 'CE Classes' }

export default async function CECoursesPage() {
  const { supabase } = await requireCEManagerPage()
  const { data: courses, error } = await supabase
    .from('ce_courses')
    .select('id, title, course_code, category, credit_hours, active, updated_at, ce_sessions(id, status, start_at)')
    .order('title')
    .limit(1000)

  return <>
    <PageHeader eyebrow="CE Tracking" title="CE Classes" description="Create reusable CE class definitions and schedule as many dates and locations as needed." action={<div className="header-actions"><Link className="secondary-button button-link" href="/ce">Back to CE</Link><Link className="primary-button button-link" href="/ce/courses/new">New CE class</Link></div>} />
    <div className="table-card">{error ? <div className="empty-state danger-text"><strong>Unable to load CE classes</strong><span>{error.message}</span></div> : (courses ?? []).length === 0 ? <div className="empty-state"><strong>No CE classes configured</strong><span>Create the first class, then add its scheduled dates and locations.</span><Link className="primary-button button-link" href="/ce/courses/new">Create first class</Link></div> : <table><thead><tr><th>Class</th><th>Category</th><th>Hours</th><th>Scheduled sessions</th><th>Status</th><th></th></tr></thead><tbody>{(courses ?? []).map((course:any) => {
      const sessions = course.ce_sessions ?? []
      const future = sessions.filter((s:any) => s.status === 'scheduled' && new Date(s.start_at) >= new Date()).length
      return <tr key={course.id}><td><strong>{course.title}</strong><div className="muted-code">{course.course_code || 'No course code'}</div></td><td>{course.category || '—'}</td><td>{Number(course.credit_hours || 0).toFixed(2)}</td><td><strong>{sessions.length}</strong><div className="muted-code">{future} upcoming</div></td><td><span className={`pill ${course.active ? 'green' : 'gray'}`}>{course.active ? 'Active' : 'Inactive'}</span></td><td className="table-action"><Link href={`/ce/courses/${course.id}`}>Open</Link></td></tr>
    })}</tbody></table>}</div>
  </>
}
