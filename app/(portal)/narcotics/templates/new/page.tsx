import type { Metadata } from 'next'
import Link from 'next/link'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { PageHeader } from '@/components/page-header'
import { createNarcoticsTemplate } from '../../actions'

export const metadata: Metadata = { title: 'New Narcotics Form' }
type Props = { searchParams: Promise<{ error?: string }> }

export default async function NewTemplatePage({ searchParams }: Props) {
  const qs = await searchParams
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')
  const { data: role } = await supabase.from('user_roles').select('role').eq('user_id', user.id).eq('role', 'system_admin').maybeSingle()
  if (!role) redirect('/narcotics')

  return <>
    <PageHeader eyebrow="Narcotics" title="New count form" description="Define a GEAEMS System controlled-substance inventory form, then assign it to one or more vehicle types." />
    {qs.error && <div className="banner danger"><div><strong>Form was not created</strong><span>{qs.error}</span></div></div>}
    <form action={createNarcoticsTemplate} className="form-card">
      <input type="hidden" name="scope_type" value="system"/>
      <div className="form-grid two">
        <label className="field"><span>Form name *</span><input name="name" required/></label>
        <label className="field span-two"><span>Description</span><textarea name="description" rows={3}/></label>
      </div>
      <div className="form-actions"><Link className="secondary-button button-link" href="/narcotics/settings">Cancel</Link><button className="primary-button" type="submit">Create form</button></div>
    </form>
  </>
}
