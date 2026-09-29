import 'server-only'
import { createClient } from '@/lib/supabase/server'

export async function requireSystemAdmin() {
  const supabase = await createClient()
  const { data: { user }, error: userError } = await supabase.auth.getUser()
  if (userError || !user) throw new Error('Authentication required.')

  const { data: role, error: roleError } = await supabase
    .from('user_roles')
    .select('role')
    .eq('user_id', user.id)
    .eq('role', 'system_admin')
    .maybeSingle()

  if (roleError || !role) throw new Error('System Administrator access is required.')
  return { supabase, user }
}
