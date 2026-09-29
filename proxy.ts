import { createServerClient } from '@supabase/ssr'
import { NextResponse, type NextRequest } from 'next/server'

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

  const [{ data: roles }, { data: profile }] = await Promise.all([
    supabase.from('user_roles').select('role').eq('user_id', user.id),
    supabase.from('profiles').select('active, provider_id').eq('id', user.id).maybeSingle(),
  ])
  if (!profile || profile.active === false) return redirectTo(request, '/auth/disabled')

  const roleNames = new Set((roles ?? []).map((row: { role: string }) => row.role))
  const isAdmin = roleNames.has('system_admin') || roleNames.has('agency_admin')
  const isSystemInspector = roleNames.has('system_inspector')
  const hasCERole = roleNames.has('ce_coordinator') || roleNames.has('ce_instructor')
  const hasProvider = !!profile.provider_id

  const defaultPath = isAdmin ? '/dashboard'
    : isSystemInspector ? '/inspections'
    : hasCERole ? '/ce'
    : hasProvider ? '/my-profile'
    : '/auth/disabled'

  if (path === '/login' || path === '/') return redirectTo(request, defaultPath)
  if (isAdmin) return supabaseResponse

  const inspectionPath = path === '/inspections' || path.startsWith('/inspections/')
  const cePath = path === '/ce' || path.startsWith('/ce/')
  const ownProfilePath = path === '/my-profile' || path.startsWith('/my-profile/')
  const narcoticsPath = path === '/narcotics' || path.startsWith('/narcotics/')

  const allowed = (isSystemInspector && inspectionPath)
    || (cePath && (hasCERole || hasProvider))
    || (hasProvider && ownProfilePath)
    || (hasProvider && narcoticsPath)

  if (!allowed) return redirectTo(request, defaultPath)
  return supabaseResponse
}

export const config = {
  matcher: ['/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)'],
}
