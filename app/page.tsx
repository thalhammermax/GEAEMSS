import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'

export default async function Home() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const { data: roles } = await supabase.from('user_roles').select('role').eq('user_id', user.id)
  const roleNames = new Set((roles ?? []).map((row: { role: string }) => row.role))
  const isAdmin = roleNames.has('system_admin') || roleNames.has('agency_admin')
  redirect(isAdmin ? '/dashboard' : '/my-profile')
}
