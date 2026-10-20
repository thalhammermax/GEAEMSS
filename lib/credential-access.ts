import { requireSession } from '@/lib/session'

export async function getCredentialAdminContext(supabase: any) {
  const session = await requireSession()
  const { user, isSystemAdmin, isAgencyAdmin } = session

  let manageableAgencies: any[] = []
  if (isSystemAdmin) {
    const { data } = await supabase.from('agencies').select('id, name, short_name, active').eq('active', true).order('name')
    manageableAgencies = data ?? []
  } else if (isAgencyAdmin) {
    const ids = session.agencyAccess.filter((r) => r.can_manage_credentials).map((r) => r.agency_id)
    if (ids.length) {
      const { data } = await supabase.from('agencies').select('id, name, short_name, active').in('id', ids).eq('active', true).order('name')
      manageableAgencies = data ?? []
    }
  }

  return { user, isSystemAdmin, isAgencyAdmin, manageableAgencies }
}
