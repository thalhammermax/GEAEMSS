import 'server-only'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'

export async function requireReportAdmin() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const [{ data: roles }, { data: profile }] = await Promise.all([
    supabase.from('user_roles').select('role').eq('user_id', user.id),
    supabase.from('profiles').select('active').eq('id', user.id).maybeSingle(),
  ])

  if (!profile || profile.active === false) redirect('/auth/disabled')
  const names = new Set((roles ?? []).map((row: any) => row.role))
  const isSystemAdmin = names.has('system_admin')
  const isAgencyAdmin = names.has('agency_admin')
  if (!isSystemAdmin && !isAgencyAdmin) redirect('/my-profile')
  return { supabase, user, isSystemAdmin, isAgencyAdmin }
}
