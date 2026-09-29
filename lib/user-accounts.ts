import 'server-only'
import { createAdminClient } from '@/lib/supabase/admin'

function siteUrl() {
  return (process.env.NEXT_PUBLIC_SITE_URL || 'https://portal.geaemss.org').replace(/\/$/, '')
}

export async function findAuthUserByEmail(email: string) {
  const admin = createAdminClient()
  let page = 1
  const perPage = 1000
  while (page <= 10) {
    const { data, error } = await admin.auth.admin.listUsers({ page, perPage })
    if (error) throw error
    const found = data.users.find((u) => u.email?.toLowerCase() === email.toLowerCase())
    if (found) return found
    if (data.users.length < perPage) return null
    page += 1
  }
  return null
}

export async function inviteProviderAccount(providerId: string) {
  const admin = createAdminClient()
  const { data: provider, error: providerError } = await admin
    .from('providers')
    .select('id, first_name, last_name, preferred_name, email')
    .eq('id', providerId)
    .single()
  if (providerError || !provider) throw providerError ?? new Error('Provider not found.')
  if (!provider.email) throw new Error('The provider must have an email address before a login can be created.')

  const { data: existingProfile, error: profileError } = await admin
    .from('profiles')
    .select('id')
    .eq('provider_id', providerId)
    .maybeSingle()
  if (profileError) throw profileError
  if (existingProfile) throw new Error('This provider already has a linked user account.')

  const existingUser = await findAuthUserByEmail(provider.email)
  const displayName = `${provider.preferred_name || provider.first_name} ${provider.last_name}`.trim()

  if (existingUser) {
    const { data: existingUserProfile, error: existingUserProfileError } = await admin
      .from('profiles')
      .select('provider_id')
      .eq('id', existingUser.id)
      .maybeSingle()
    if (existingUserProfileError) throw existingUserProfileError
    if (existingUserProfile?.provider_id && existingUserProfile.provider_id !== provider.id) {
      throw new Error('That email address is already linked to a different provider account.')
    }

    const { error: profileInsertError } = await admin.from('profiles').upsert({
      id: existingUser.id,
      provider_id: provider.id,
      display_name: displayName,
      active: true,
    }, { onConflict: 'id' })
    if (profileInsertError) throw profileInsertError
    const { error: roleError } = await admin.from('user_roles').upsert({ user_id: existingUser.id, role: 'provider' }, { onConflict: 'user_id,role' })
    if (roleError) throw roleError

    const { error: resetError } = await admin.auth.resetPasswordForEmail(provider.email, {
      redirectTo: `${siteUrl()}/auth/setup-password?provider=${encodeURIComponent(provider.id)}`,
    })
    if (resetError) throw resetError
    return { userId: existingUser.id, mode: 'reset' as const }
  }

  const { data: invite, error: inviteError } = await admin.auth.admin.inviteUserByEmail(provider.email, {
    data: { display_name: displayName, provider_id: provider.id },
    redirectTo: `${siteUrl()}/auth/setup-password?provider=${encodeURIComponent(provider.id)}`,
  })
  if (inviteError || !invite.user) throw inviteError ?? new Error('Supabase did not return the invited user.')

  const { error: profileInsertError } = await admin.from('profiles').upsert({
    id: invite.user.id,
    provider_id: provider.id,
    display_name: displayName,
    active: true,
  }, { onConflict: 'id' })
  if (profileInsertError) throw profileInsertError

  const { error: roleError } = await admin.from('user_roles').upsert({ user_id: invite.user.id, role: 'provider' }, { onConflict: 'user_id,role' })
  if (roleError) throw roleError

  return { userId: invite.user.id, mode: 'invite' as const }
}

export async function sendPasswordSetupEmail(email: string, expectedUserId: string) {
  const admin = createAdminClient()
  const { error } = await admin.auth.resetPasswordForEmail(email, {
    redirectTo: `${siteUrl()}/auth/setup-password?uid=${encodeURIComponent(expectedUserId)}`,
  })
  if (error) throw error
}
