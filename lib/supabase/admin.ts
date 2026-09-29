import 'server-only'
import { createClient } from '@supabase/supabase-js'

export function createAdminClient() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL
  const secret = process.env.SUPABASE_SECRET_KEY || process.env.SUPABASE_SERVICE_ROLE_KEY

  if (!url || !secret) {
    throw new Error('Server-side Supabase admin access is not configured. Add SUPABASE_SECRET_KEY to the Netlify environment variables (or SUPABASE_SERVICE_ROLE_KEY if you are using a legacy key).')
  }

  return createClient(url, secret, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
      detectSessionInUrl: false,
    },
  })
}
