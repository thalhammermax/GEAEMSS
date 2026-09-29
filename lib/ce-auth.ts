import 'server-only'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'

export async function getCEContext() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const [{ data: profile }, { data: roles }] = await Promise.all([
    supabase.from('profiles').select('provider_id, display_name, active').eq('id', user.id).maybeSingle(),
    supabase.from('user_roles').select('role').eq('user_id', user.id),
  ])
  if (!profile || profile.active === false) redirect('/auth/disabled')

  const roleNames = new Set((roles ?? []).map((r: any) => r.role))
  const isSystemAdmin = roleNames.has('system_admin')
  const isCECoordinator = roleNames.has('ce_coordinator')
  const isCEInstructor = roleNames.has('ce_instructor')

  return {
    supabase,
    user,
    profile,
    roleNames,
    isSystemAdmin,
    isCECoordinator,
    isCEInstructor,
    canManageCE: isSystemAdmin || isCECoordinator,
    providerId: profile.provider_id as string | null,
  }
}

export async function requireCEManager() {
  const context = await getCEContext()
  if (!context.canManageCE) throw new Error('CE Coordinator access is required.')
  return context
}

export async function requireCESessionManager(sessionId: string) {
  const context = await getCEContext()
  if (context.canManageCE) return context
  if (!context.isCEInstructor) throw new Error('CE Instructor access is required.')

  const { data: assignment, error } = await context.supabase
    .from('ce_session_instructors')
    .select('session_id')
    .eq('session_id', sessionId)
    .eq('user_id', context.user.id)
    .maybeSingle()
  if (error) throw error
  if (!assignment) throw new Error('You are not assigned to this CE session.')
  return context
}

export async function requireCEManagerPage() {
  const context = await getCEContext()
  if (!context.canManageCE) redirect('/ce')
  return context
}

export async function requireCESessionManagerPage(sessionId: string) {
  const context = await getCEContext()
  if (context.canManageCE) return context
  if (!context.isCEInstructor) redirect('/ce')
  const { data: assignment } = await context.supabase
    .from('ce_session_instructors')
    .select('session_id')
    .eq('session_id', sessionId)
    .eq('user_id', context.user.id)
    .maybeSingle()
  if (!assignment) redirect('/ce')
  return context
}
