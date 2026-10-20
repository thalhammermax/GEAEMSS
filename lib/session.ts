import 'server-only'
import { cache } from 'react'
import { headers } from 'next/headers'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { defaultModuleStates, MODULE_CATALOG, type ModuleKey, type ModuleStateMap } from '@/lib/modules'

export const SESSION_HEADER = 'x-geaems-session'

export type AgencyAccess = {
  agency_id: string
  can_manage_personnel: boolean
  can_manage_credentials: boolean
  can_manage_fleet: boolean
  can_manage_narcotics: boolean
}

export type SessionUser = { id: string; email: string | null }

export type SessionContext = {
  user: SessionUser
  profileExists: boolean
  active: boolean
  providerId: string | null
  displayName: string | null
  roles: string[]
  agencyAccess: AgencyAccess[]
  modules: ModuleStateMap
  // Derived convenience flags
  isSystemAdmin: boolean
  isAgencyAdmin: boolean
  isAdmin: boolean
  isSystemInspector: boolean
  isCECoordinator: boolean
  isCEInstructor: boolean
  hasProvider: boolean
}

type RawContext = {
  user_id: string
  email: string | null
  profile_exists: boolean
  active: boolean
  provider_id: string | null
  display_name: string | null
  roles: string[]
  agency_access: AgencyAccess[]
  modules: Record<string, boolean>
}

export function buildSessionContext(raw: RawContext): SessionContext {
  const roles = raw.roles ?? []
  const has = (role: string) => roles.includes(role)
  const modules = defaultModuleStates()
  for (const module of MODULE_CATALOG) {
    const value = raw.modules?.[module.key]
    if (typeof value === 'boolean') modules[module.key] = value
  }
  const isSystemAdmin = has('system_admin')
  const isAgencyAdmin = has('agency_admin')
  return {
    user: { id: raw.user_id, email: raw.email ?? null },
    profileExists: raw.profile_exists === true,
    active: raw.active === true,
    providerId: raw.provider_id ?? null,
    displayName: raw.display_name ?? null,
    roles,
    agencyAccess: raw.agency_access ?? [],
    modules,
    isSystemAdmin,
    isAgencyAdmin,
    isAdmin: isSystemAdmin || isAgencyAdmin,
    isSystemInspector: has('system_inspector'),
    isCECoordinator: has('ce_coordinator'),
    isCEInstructor: has('ce_instructor'),
    hasProvider: !!raw.provider_id,
  }
}

export function encodeSessionHeader(raw: RawContext) {
  return Buffer.from(JSON.stringify(raw), 'utf8').toString('base64url')
}

function decodeSessionHeader(value: string | null): RawContext | null {
  if (!value) return null
  try {
    return JSON.parse(Buffer.from(value, 'base64url').toString('utf8')) as RawContext
  } catch {
    return null
  }
}

/**
 * Resolves the signed-in user and their authorization context ONCE per request.
 *
 * Fast path: the proxy already verified the JWT and ran get_session_context(),
 * and forwarded the result in a request header. We still verify the JWT locally
 * (no network when asymmetric signing keys are enabled) and only accept the
 * forwarded context when it belongs to the same user id as the token.
 *
 * Fallback: run the RPC ourselves (one round trip).
 */
export const getSessionContext = cache(async (): Promise<SessionContext | null> => {
  const supabase = await createClient()
  const { data: claimsData } = await supabase.auth.getClaims()
  const userId = claimsData?.claims?.sub
  if (!userId) return null

  const headerStore = await headers()
  const forwarded = decodeSessionHeader(headerStore.get(SESSION_HEADER))
  if (forwarded && forwarded.user_id === userId) return buildSessionContext(forwarded)

  const { data, error } = await supabase.rpc('get_session_context')
  if (error || !data) {
    // Migration 023 not applied yet: degrade to the legacy multi-query path.
    const [{ data: roles }, { data: profile }, { data: moduleRows }, { data: access }] = await Promise.all([
      supabase.from('user_roles').select('role').eq('user_id', userId),
      supabase.from('profiles').select('active, provider_id, display_name').eq('id', userId).maybeSingle(),
      supabase.from('system_module_settings').select('module_key, enabled'),
      supabase.from('user_agency_access').select('agency_id, can_manage_personnel, can_manage_credentials, can_manage_fleet, can_manage_narcotics').eq('user_id', userId),
    ])
    return buildSessionContext({
      user_id: userId,
      email: (claimsData?.claims as any)?.email ?? null,
      profile_exists: !!profile,
      active: profile?.active !== false && !!profile,
      provider_id: profile?.provider_id ?? null,
      display_name: profile?.display_name ?? null,
      roles: (roles ?? []).map((r: any) => r.role),
      agency_access: (access ?? []) as AgencyAccess[],
      modules: Object.fromEntries((moduleRows ?? []).map((r: any) => [r.module_key, r.enabled !== false])),
    })
  }
  return buildSessionContext(data as RawContext)
})

/** Signed-in, active user or redirect. Use instead of supabase.auth.getUser() in pages. */
export async function requireSession(): Promise<SessionContext> {
  const session = await getSessionContext()
  if (!session) redirect('/login')
  if (!session.profileExists || !session.active) redirect('/auth/disabled')
  return session
}

/** Minimal user object ({ id, email }) for pages that only need the identity. */
export async function requireUser(): Promise<SessionUser> {
  return (await requireSession()).user
}

export function moduleEnabled(session: SessionContext, key: ModuleKey) {
  return session.modules[key]
}

// ---------------------------------------------------------------------------
// PostgREST-shaped accessors backed by the cached session. These let existing
// pages drop their per-page user_roles / user_agency_access queries without
// restructuring the surrounding Promise.all() calls.
// ---------------------------------------------------------------------------
export async function sessionRoleRows() {
  const session = await requireSession()
  return { data: session.roles.map((role) => ({ role })), error: null }
}

export async function sessionSystemAdminRole() {
  const session = await requireSession()
  return { data: session.isSystemAdmin ? { role: 'system_admin' } : null, error: null }
}

export async function sessionAgencyAccessRows() {
  const session = await requireSession()
  return { data: session.agencyAccess, error: null }
}
