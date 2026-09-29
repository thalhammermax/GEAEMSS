import type { Metadata } from 'next'
import Link from 'next/link'
import { PageHeader } from '@/components/page-header'
import { getCEContext } from '@/lib/ce-auth'
import { submitExternalCE } from '../../actions'

export const metadata: Metadata = { title: 'Submit External CE' }
type Props = { searchParams: Promise<{ error?: string }> }

export default async function NewExternalCEPage({ searchParams }: Props) {
  const qs = await searchParams
  const { providerId } = await getCEContext()
  if (!providerId) return <><PageHeader title="External CE" description="A linked provider record is required to submit CE."/><div className="empty-state"><strong>No linked provider record</strong><span>Ask System Administration to link this account to your provider record.</span></div></>

  return <>
    <PageHeader eyebrow="CE Tracking" title="Submit External / Online CE" description="Upload completion documentation for training completed outside a GEAEMS electronic session." action={<Link className="secondary-button button-link" href="/ce">Back to CE</Link>} />
    {qs.error && <div className="banner danger"><div><strong>Submission failed</strong><span>{qs.error}</span></div></div>}
    <div className="banner info"><div><strong>When to use this form</strong><span>Use this for online or outside-system CE such as mandated reporter training. BLS, ACLS, PALS, state licenses, and other standing certifications should still be submitted under Credentials.</span></div></div>
    <section className="form-card">
      <form action={submitExternalCE}>
        <div className="form-card-heading"><div><span>Completion documentation</span><h2>Training information</h2></div></div>
        <div className="form-grid">
          <label className="field span-full"><span>Training / course title</span><input name="title" required placeholder="Example: Illinois Mandated Reporter Training"/></label>
          <label className="field"><span>Training provider / sponsor</span><input name="sponsor" placeholder="DCFS, hospital, TargetSolutions, etc."/></label>
          <label className="field"><span>Category</span><input name="category" placeholder="Mandated, Medical, Trauma, Pediatrics, etc."/></label>
          <label className="field"><span>Completion date</span><input type="date" name="completion_date" required/></label>
          <label className="field"><span>CE hours</span><input type="number" min="0" step="0.25" name="credit_hours" required defaultValue="1"/><small>Enter 0 if the training must be tracked but does not award CE hours.</small></label>
          <label className="field span-full"><span>Completion certificate</span><input type="file" name="certificate" accept="application/pdf,image/jpeg,image/png,image/webp" required/><small>PDF, JPG, PNG, or WebP. Maximum 10 MB.</small></label>
          <label className="field span-full"><span>Notes</span><textarea name="notes" rows={4} placeholder="Optional context for the CE Coordinator."/></label>
        </div>
        <div className="form-actions"><Link className="secondary-button button-link" href="/ce">Cancel</Link><button className="primary-button" type="submit">Submit for CE review</button></div>
      </form>
    </section>
  </>
}
