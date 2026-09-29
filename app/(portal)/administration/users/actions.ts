'use server'

import { revalidatePath } from 'next/cache'
import { redirect } from 'next/navigation'
import { createAdminClient } from '@/lib/supabase/admin'
import { requireSystemAdmin } from '@/lib/admin-auth'
import { inviteProviderAccount, sendPasswordSetupEmail } from '@/lib/user-accounts'

function value(formData: FormData, key: string) {
  const v = formData.get(key)
  return typeof v === 'string' ? v.trim() : ''
}
function checked(formData: FormData, key: string) { return formData.get(key) === 'on' }
function fail(path: string, message: string): never { redirect(`${path}?error=${encodeURIComponent(message)}`) }

export async function inviteProviderUser(formData: FormData) {
  const providerId = value(formData, 'provider_id')
  if (!providerId) fail('/administration/users', 'Provider is required.')
  try {
    await requireSystemAdmin()
    const result = await inviteProviderAccount(providerId)
    revalidatePath('/administration/users')
    revalidatePath(`/personnel/${providerId}`)
    redirect('/administration/users?notice=' + encodeURIComponent(result.mode === 'invite' ? 'Account invitation sent.' : 'Existing account linked and password setup email sent.'))
  } catch (error: any) {
    fail('/administration/users', error?.message ?? 'The account invitation could not be sent.')
  }
}

export async function resendPasswordSetup(formData: FormData) {
  const userId = value(formData, 'user_id')
  if (!userId) fail('/administration/users', 'User ID is required.')
  try {
    await requireSystemAdmin()
    const admin = createAdminClient()
    const { data, error } = await admin.auth.admin.getUserById(userId)
    if (error || !data.user?.email) throw error ?? new Error('User email not found.')
    await sendPasswordSetupEmail(data.user.email, userId)
    redirect(`/administration/users/${userId}?notice=${encodeURIComponent('Password setup/reset email sent.')}`)
  } catch (error: any) {
    fail(`/administration/users/${userId}`, error?.message ?? 'Email could not be sent.')
  }
}

export async function setUserActive(formData: FormData) {
  const userId = value(formData, 'user_id')
  const active = value(formData, 'active') === 'true'
  if (!userId) fail('/administration/users', 'User ID is required.')
  try {
    const { supabase, user } = await requireSystemAdmin()
    if (user.id === userId && !active) throw new Error('You cannot disable your own account.')
    const { error } = await supabase.from('profiles').update({ active }).eq('id', userId)
    if (error) throw error
    revalidatePath('/administration/users')
    revalidatePath(`/administration/users/${userId}`)
    redirect(`/administration/users/${userId}?notice=${encodeURIComponent(active ? 'User access enabled.' : 'User access disabled.')}`)
  } catch (error: any) {
    fail(`/administration/users/${userId}`, error?.message ?? 'User status could not be changed.')
  }
}

export async function saveUserRoles(formData: FormData) {
  const userId = value(formData, 'user_id')
  if (!userId) fail('/administration/users', 'User ID is required.')
  const requested = new Set(formData.getAll('roles').filter((x): x is string => typeof x === 'string'))
  const allowed = ['provider','agency_admin','system_inspector','system_admin']
  const roles = allowed.filter((r) => requested.has(r))
  try {
    const { supabase, user } = await requireSystemAdmin()
    if (user.id === userId && !roles.includes('system_admin')) throw new Error('You cannot remove your own System Administrator role.')
    const { error: deleteError } = await supabase.from('user_roles').delete().eq('user_id', userId)
    if (deleteError) throw deleteError
    if (roles.length) {
      const { error: insertError } = await supabase.from('user_roles').insert(roles.map((role) => ({ user_id: userId, role })))
      if (insertError) throw insertError
    }
    // Agency permission rows are meaningful only for Agency Administrators.
    // Clear them on demotion so stale permissions cannot later become active unexpectedly.
    if (!roles.includes('agency_admin')) {
      const { error: accessDeleteError } = await supabase.from('user_agency_access').delete().eq('user_id', userId)
      if (accessDeleteError) throw accessDeleteError
    }
    revalidatePath('/administration/users')
    revalidatePath(`/administration/users/${userId}`)
    redirect(`/administration/users/${userId}?notice=${encodeURIComponent('Roles updated.')}`)
  } catch (error: any) {
    fail(`/administration/users/${userId}`, error?.message ?? 'Roles could not be updated.')
  }
}

export async function saveAgencyAccess(formData: FormData) {
  const userId = value(formData, 'user_id')
  const agencyId = value(formData, 'agency_id')
  if (!userId || !agencyId) fail('/administration/users', 'User and agency are required.')
  try {
    const { supabase } = await requireSystemAdmin()
    const { data: agencyAdminRole, error: roleError } = await supabase
      .from('user_roles')
      .select('role')
      .eq('user_id', userId)
      .eq('role', 'agency_admin')
      .maybeSingle()
    if (roleError) throw roleError
    if (!agencyAdminRole) throw new Error('Agency permissions can only be assigned to a user with the Agency Administrator role.')
    if (checked(formData, 'enabled')) {
      const { error } = await supabase.from('user_agency_access').upsert({
        user_id: userId,
        agency_id: agencyId,
        can_manage_personnel: checked(formData, 'can_manage_personnel'),
        can_manage_credentials: checked(formData, 'can_manage_credentials'),
        can_manage_fleet: checked(formData, 'can_manage_fleet'),
      }, { onConflict: 'user_id,agency_id' })
      if (error) throw error
    } else {
      const { error } = await supabase.from('user_agency_access').delete().eq('user_id', userId).eq('agency_id', agencyId)
      if (error) throw error
    }
    revalidatePath(`/administration/users/${userId}`)
    redirect(`/administration/users/${userId}?notice=${encodeURIComponent('Agency access updated.')}`)
  } catch (error: any) {
    fail(`/administration/users/${userId}`, error?.message ?? 'Agency access could not be updated.')
  }
}
