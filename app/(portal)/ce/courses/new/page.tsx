import type { Metadata } from 'next'
import Link from 'next/link'
import { PageHeader } from '@/components/page-header'
import { requireCEManagerPage } from '@/lib/ce-auth'
import { createCECourse } from '../../actions'

export const metadata: Metadata = { title: 'New CE Class' }
type Props = { searchParams: Promise<{ error?: string }> }

export default async function NewCECoursePage({ searchParams }: Props) {
  const qs = await searchParams
  await requireCEManagerPage()
  return <>
    <PageHeader eyebrow="CE Tracking" title="New CE Class" description="Create the class once, then add one or more scheduled dates and locations." action={<Link className="secondary-button button-link" href="/ce/courses">Back to classes</Link>} />
    {qs.error && <div className="banner danger"><div><strong>Class could not be created</strong><span>{qs.error}</span></div></div>}
    <section className="form-card">
      <form action={createCECourse}>
        <div className="form-card-heading"><div><span>Class definition</span><h2>CE information</h2></div></div>
        <div className="form-grid">
          <label className="field span-full"><span>Class title</span><input name="title" required placeholder="Example: September System CE" /></label>
          <label className="field"><span>Course code</span><input name="course_code" placeholder="Optional" /></label>
          <label className="field"><span>Category</span><input name="category" placeholder="Medical, Trauma, Pediatrics, Mandated, etc." /></label>
          <label className="field"><span>CE hours</span><input name="credit_hours" type="number" min="0" step="0.25" defaultValue="1" required /></label>
          <label className="field span-full"><span>Description</span><textarea name="description" rows={5} placeholder="Course objectives, audience, or other information shown to providers." /></label>
        </div>
        <div className="form-actions"><Link className="secondary-button button-link" href="/ce/courses">Cancel</Link><button className="primary-button" type="submit">Create class & schedule sessions</button></div>
      </form>
    </section>
  </>
}
