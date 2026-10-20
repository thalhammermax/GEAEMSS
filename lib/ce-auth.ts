import 'server-only'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { requireSession } from '@/lib/session'

export async function getCEContext() {
  const supabase = await createClient()
  const session = await requireSession()
  const roleNames = new Set(session.roles)
  const isSystemAdmin = session.isSystemAdmin
  const isCECoordinator = session.isCECoordinator
  const isCEInstructor = session.isCEInstructor

  return {
    supabase,
    user: session.user,
    profile: { provider_id: session.providerId, display_name: session.displayName, active: session.active },
    roleNames,
    isSystemAdmin,
    isCECoordinator,
    isCEInstructor,
    canManageCE: isSystemAdmin || isCECoordinator,
    providerId: session.providerId,
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
