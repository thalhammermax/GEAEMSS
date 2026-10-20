import { createServerClient } from '@supabase/ssr'
import { NextResponse, type NextRequest } from 'next/server'
import { defaultModuleStates, MODULE_CATALOG, moduleForPath } from '@/lib/modules'

const SESSION_HEADER = 'x-geaems-session'

function redirectTo(request: NextRequest, pathname: string, cookies: PendingCookie[]) {
  const url = request.nextUrl.clone()
  url.pathname = pathname
  url.search = ''
  const response = NextResponse.redirect(url)
  applyCookies(response, cookies)
  return response
}

type PendingCookie = { name: string; value: string; options?: Parameters<NextResponse['cookies']['set']>[2] }

function applyCookies(response: NextResponse, cookies: PendingCookie[]) {
  cookies.forEach(({ name, value, options }) => response.cookies.set(name, value, options))
}

function toBase64Url(value: string) {
  // btoa is available in both the Edge and Node runtimes.
  const bytes = new TextEncoder().encode(value)
  let binary = ''
  bytes.forEach((b) => { binary += String.fromCharCode(b) })
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
}

export async function proxy(request: NextRequest) {
  // Never trust a session header supplied by the browser.
  const forwardedHeaders = new Headers(request.headers)
  forwardedHeaders.delete(SESSION_HEADER)

  const pendingCookies: PendingCookie[] = []
  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!,
    {
      cookies: {
        getAll() { return request.cookies.getAll() },
        setAll(cookiesToSet) {
          cookiesToSet.forEach(({ name, value, options }) => {
            request.cookies.set(name, value)
            pendingCookies.push({ name, value, options })
          })
        },
      },
    }
  )

  // getClaims() verifies the JWT signature locally against the project's
  // public signing key (cached), refreshing the session when needed. Unlike
  // getUser() it does not call the Supabase Auth server on every request.
  const { data: claimsData } = await supabase.auth.getClaims()
  const userId = claimsData?.claims?.sub
  const path = request.nextUrl.pathname
  const isPublic = path.startsWith('/login') || path.startsWith('/auth')

  const next = () => {
    const response = NextResponse.next({ request: { headers: forwardedHeaders } })
    applyCookies(response, pendingCookies)
    return response
  }

  if (!userId && !isPublic) return redirectTo(request, '/login', pendingCookies)
  if (!userId) return next()
  if (path.startsWith('/auth')) return next()

  // One round trip for roles + profile + agency access + module rollout.
  const { data: context, error } = await supabase.rpc('get_session_context')
  if (error || !context) {
    // Migration 023 not applied yet: let the layout do the legacy lookups.
    return next()
  }

  forwardedHeaders.set(SESSION_HEADER, toBase64Url(JSON.stringify(context)))

  if (!context.profile_exists || context.active === false) return redirectTo(request, '/auth/disabled', pendingCookies)

  const moduleStates = defaultModuleStates()
  for (const module of MODULE_CATALOG) {
    const value = context.modules?.[module.key]
    if (typeof value === 'boolean') moduleStates[module.key] = value
  }

  const roleNames = new Set<string>(context.roles ?? [])
  const isSystemAdmin = roleNames.has('system_admin')
  const isAdmin = isSystemAdmin || roleNames.has('agency_admin')
  const isSystemInspector = roleNames.has('system_inspector')
  const hasCERole = roleNames.has('ce_coordinator') || roleNames.has('ce_instructor')
  const hasProvider = !!context.provider_id

  const routeModule = moduleForPath(path)
  if (routeModule && !moduleStates[routeModule] && !isSystemAdmin) {
    return redirectTo(request, '/dashboard', pendingCookies)
  }

  const defaultPath = isAdmin ? '/dashboard'
    : isSystemInspector && moduleStates.inspections ? '/inspections'
    : hasCERole && moduleStates.ce ? '/ce'
    : hasProvider && moduleStates.personnel ? '/my-profile'
    : hasProvider && moduleStates.narcotics ? '/narcotics'
    : '/auth/disabled'

  if (path === '/login' || path === '/') return redirectTo(request, defaultPath, pendingCookies)
  if (isAdmin) return next()

  const inspectionPath = path === '/inspections' || path.startsWith('/inspections/')
  const cePath = path === '/ce' || path.startsWith('/ce/')
  const ownProfilePath = path === '/my-profile' || path.startsWith('/my-profile/')
  const narcoticsPath = path === '/narcotics' || path.startsWith('/narcotics/')

  const allowed = (isSystemInspector && moduleStates.inspections && inspectionPath)
    || (moduleStates.ce && cePath && (hasCERole || hasProvider))
    || (moduleStates.personnel && hasProvider && ownProfilePath)
    || (moduleStates.narcotics && hasProvider && narcoticsPath)

  if (!allowed) return redirectTo(request, defaultPath, pendingCookies)
  return next()
}

export const config = {
  matcher: ['/((?!_next/static|_next/image|favicon.ico|manifest.webmanifest|icons/|.*\\.(?:svg|png|jpg|jpeg|gif|webp|ico)$).*)'],
}
