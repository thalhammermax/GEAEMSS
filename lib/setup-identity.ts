import 'server-only'
import type { createClient } from '@/lib/supabase/server'

export const WRONG_USER_MESSAGE = 'This password setup link belongs to a different portal user. Sign out of the portal or open the email link in a private/incognito window, then try again.'

export async function validateSetupIdentity(
  supabase: Awaited<ReturnType<typeof createClient>>,
  expectedUserId: string | null,
  expectedProviderId: string | null,
): Promise<{ error?: string; email?: string }> {
  if (!expectedUserId && !expectedProviderId) {
    return { error: 'This password setup link is missing its account identity. Ask a System Administrator to send a new setup email.' }
  }
  const { data: { user }, error } = await supabase.auth.getUser()
  if (error || !user) {
    return { error: 'This setup link is invalid, has expired, or has not finished signing you in. Ask a System Administrator to send a new password setup email.' }
  }
  if (expectedUserId && user.id !== expectedUserId) return { error: WRONG_USER_MESSAGE }
  if (expectedProviderId) {
    const { data: profile, error: profileError } = await supabase.from('profiles').select('provider_id').eq('id', user.id).maybeSingle()
    if (profileError || profile?.provider_id !== expectedProviderId) return { error: WRONG_USER_MESSAGE }
  }
  return { email: user.email ?? '' }
}
