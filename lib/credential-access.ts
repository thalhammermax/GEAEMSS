import { redirect } from 'next/navigation'

export async function getCredentialAdminContext(supabase: any) {
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const [{ data: roles }, { data: accessRows }] = await Promise.all([
    supabase.from('user_roles').select('role').eq('user_id', user.id),
    supabase.from('user_agency_access').select('agency_id, can_manage_credentials').eq('user_id', user.id),
  ])

  const roleNames = new Set((roles ?? []).map((r: any) => r.role))
  const isSystemAdmin = roleNames.has('system_admin')
  const isAgencyAdmin = roleNames.has('agency_admin')

  let manageableAgencies: any[] = []
  if (isSystemAdmin) {
    const { data } = await supabase.from('agencies').select('id, name, short_name, active').eq('active', true).order('name')
    manageableAgencies = data ?? []
  } else if (isAgencyAdmin) {
    const ids = (accessRows ?? []).filter((r: any) => r.can_manage_credentials).map((r: any) => r.agency_id)
    if (ids.length) {
      const { data } = await supabase.from('agencies').select('id, name, short_name, active').in('id', ids).eq('active', true).order('name')
      manageableAgencies = data ?? []
    }
  }

  return { user, isSystemAdmin, isAgencyAdmin, manageableAgencies }
}
