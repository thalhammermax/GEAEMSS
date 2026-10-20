import 'server-only'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { requireSession } from '@/lib/session'

export async function requireReportAdmin() {
  const supabase = await createClient()
  const session = await requireSession()
  if (!session.isSystemAdmin && !session.isAgencyAdmin) redirect('/my-profile')
  return { supabase, user: session.user, isSystemAdmin: session.isSystemAdmin, isAgencyAdmin: session.isAgencyAdmin }
}
