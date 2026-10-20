import 'server-only'
import { createClient } from '@/lib/supabase/server'
import { getSessionContext } from '@/lib/session'

export async function requireSystemAdmin() {
  const supabase = await createClient()
  const session = await getSessionContext()
  if (!session) throw new Error('Authentication required.')
  if (!session.active || !session.isSystemAdmin) throw new Error('System Administrator access is required.')
  return { supabase, user: session.user }
}
