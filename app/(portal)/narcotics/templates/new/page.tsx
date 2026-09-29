import type { Metadata } from 'next'
import Link from 'next/link'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { PageHeader } from '@/components/page-header'
import { createNarcoticsTemplate } from '../../actions'

export const metadata: Metadata = { title: 'New Narcotics Template' }
type Props = { searchParams: Promise<{ error?: string }> }
export default async function NewTemplatePage({ searchParams }: Props) {
  const qs = await searchParams
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')
  const [{ data: roles }, { data: agencies }, { data: access }] = await Promise.all([
    supabase.from('user_roles').select('role').eq('user_id', user.id),
    supabase.from('agencies').select('id, name').eq('active', true).order('name'),
    supabase.from('user_agency_access').select('agency_id, can_manage_narcotics').eq('user_id', user.id),
  ])
  const roleNames = new Set((roles ?? []).map((r:any) => r.role))
  const isSystemAdmin = roleNames.has('system_admin')
  const allowedAgencyIds = new Set((access ?? []).filter((a:any) => a.can_manage_narcotics).map((a:any) => a.agency_id))
  const manageable = (agencies ?? []).filter((a:any) => isSystemAdmin || allowedAgencyIds.has(a.id))
  if (!isSystemAdmin && manageable.length === 0) redirect('/narcotics')
  return <><PageHeader eyebrow="Narcotics" title="New count template" description="Define the inventory list and expected quantities for a daily apparatus count." />{qs.error && <div className="banner danger"><div><strong>Template was not created</strong><span>{qs.error}</span></div></div>}<form action={createNarcoticsTemplate} className="form-card"><div className="form-grid three"><label className="field"><span>Template name *</span><input name="name" required/></label>{isSystemAdmin ? <label className="field"><span>Scope</span><select name="scope_type" defaultValue="system"><option value="system">GEAEMS System</option><option value="agency">Agency</option></select></label> : <input type="hidden" name="scope_type" value="agency"/>}<label className="field"><span>Agency{isSystemAdmin ? ' (agency scope only)' : ' *'}</span><select name="agency_id" defaultValue=""><option value="">Select agency</option>{manageable.map((a:any) => <option key={a.id} value={a.id}>{a.name}</option>)}</select></label><label className="field span-full"><span>Description</span><textarea name="description" rows={3}/></label></div><div className="form-actions"><Link className="secondary-button button-link" href="/narcotics/settings">Cancel</Link><button className="primary-button" type="submit">Create template</button></div></form></>
}
