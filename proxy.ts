import { createServerClient } from '@supabase/ssr'
import { NextResponse, type NextRequest } from 'next/server'
import { defaultModuleStates, MODULE_CATALOG, moduleForPath } from '@/lib/modules'

function redirectTo(request: NextRequest, pathname: string) {
  const url = request.nextUrl.clone()
  url.pathname = pathname
  url.search = ''
  return NextResponse.redirect(url)
}

export async function proxy(request: NextRequest) {
  let supabaseResponse = NextResponse.next({ request })

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!,
    {
      cookies: {
        getAll() { return request.cookies.getAll() },
        setAll(cookiesToSet, headers) {
          cookiesToSet.forEach(({ name, value }) => request.cookies.set(name, value))
          supabaseResponse = NextResponse.next({ request })
          cookiesToSet.forEach(({ name, value, options }) => supabaseResponse.cookies.set(name, value, options))
          Object.entries(headers).forEach(([key, value]) => supabaseResponse.headers.set(key, value))
        },
      },
    }
  )

  const { data: { user } } = await supabase.auth.getUser()
  const path = request.nextUrl.pathname
  const isPublic = path.startsWith('/login') || path.startsWith('/auth')

  if (!user && !isPublic) return redirectTo(request, '/login')
  if (!user) return supabaseResponse
  if (path.startsWith('/auth')) return supabaseResponse

  const [{ data: roles }, { data: profile }, { data: moduleRows }] = await Promise.all([
    supabase.from('user_roles').select('role').eq('user_id', user.id),
    supabase.from('profiles').select('active, provider_id').eq('id', user.id).maybeSingle(),
    supabase.from('system_module_settings').select('module_key, enabled'),
  ])
  if (!profile || profile.active === false) return redirectTo(request, '/auth/disabled')

  const moduleStates = defaultModuleStates()
  for (const row of moduleRows ?? []) {
    if (MODULE_CATALOG.some((module) => module.key === row.module_key)) {
      moduleStates[row.module_key as keyof typeof moduleStates] = row.enabled !== false
    }
  }

  const roleNames = new Set((roles ?? []).map((row: { role: string }) => row.role))
  const isSystemAdmin = roleNames.has('system_admin')
  const isAdmin = isSystemAdmin || roleNames.has('agency_admin')
  const isSystemInspector = roleNames.has('system_inspector')
  const hasCERole = roleNames.has('ce_coordinator') || roleNames.has('ce_instructor')
  const hasProvider = !!profile.provider_id

  const routeModule = moduleForPath(path)
  if (routeModule && !moduleStates[routeModule] && !isSystemAdmin) {
    return redirectTo(request, '/dashboard')
  }

  const defaultPath = isAdmin ? '/dashboard'
    : isSystemInspector && moduleStates.inspections ? '/inspections'
    : hasCERole && moduleStates.ce ? '/ce'
    : hasProvider && moduleStates.personnel ? '/my-profile'
    : hasProvider && moduleStates.narcotics ? '/narcotics'
    : '/auth/disabled'

  if (path === '/login' || path === '/') return redirectTo(request, defaultPath)
  if (isAdmin) return supabaseResponse

  const inspectionPath = path === '/inspections' || path.startsWith('/inspections/')
  const cePath = path === '/ce' || path.startsWith('/ce/')
  const ownProfilePath = path === '/my-profile' || path.startsWith('/my-profile/')
  const narcoticsPath = path === '/narcotics' || path.startsWith('/narcotics/')

  const allowed = (isSystemInspector && moduleStates.inspections && inspectionPath)
    || (moduleStates.ce && cePath && (hasCERole || hasProvider))
    || (moduleStates.personnel && hasProvider && ownProfilePath)
    || (moduleStates.narcotics && hasProvider && narcoticsPath)

  if (!allowed) return redirectTo(request, defaultPath)
  return supabaseResponse
}

export const config = {
  matcher: ['/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)'],
}
