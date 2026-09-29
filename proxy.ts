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
        getAll() {
          return request.cookies.getAll()
        },
        setAll(cookiesToSet, headers) {
          cookiesToSet.forEach(({ name, value }) => request.cookies.set(name, value))
          supabaseResponse = NextResponse.next({ request })
          cookiesToSet.forEach(({ name, value, options }) =>
            supabaseResponse.cookies.set(name, value, options)
          )
          Object.entries(headers).forEach(([key, value]) =>
            supabaseResponse.headers.set(key, value)
          )
        },
      },
    }
  )

  const { data: { user } } = await supabase.auth.getUser()
  const path = request.nextUrl.pathname
  const isPublic = path.startsWith('/login') || path.startsWith('/auth')

  if (!user && !isPublic) return redirectTo(request, '/login')
  if (!user) return supabaseResponse

  // Public auth routes must remain reachable while an invite/recovery session is active.
  if (path.startsWith('/auth')) return supabaseResponse

  const [{ data: roles }, { data: profile }] = await Promise.all([
    supabase.from('user_roles').select('role').eq('user_id', user.id),
    supabase.from('profiles').select('active, provider_id').eq('id', user.id).maybeSingle(),
  ])

  if (!profile || profile.active === false) return redirectTo(request, '/auth/disabled')

  const roleNames = new Set((roles ?? []).map((row: { role: string }) => row.role))
  const isAdmin = roleNames.has('system_admin') || roleNames.has('agency_admin')
  const isSystemInspector = roleNames.has('system_inspector')

  if (path === '/login') {
    return redirectTo(request, isAdmin ? '/dashboard' : isSystemInspector ? '/inspections' : '/my-profile')
  }

  // A pure System Inspector gets an inspection-focused workspace. The role is
  // intentionally not an administrative role and does not unlock Fleet,
  // Personnel, Reports, Credentials, or Administration pages.
  if (!isAdmin && isSystemInspector) {
    if (path === '/') return redirectTo(request, '/inspections')
    const inspectionPath = path === '/inspections' || path.startsWith('/inspections/')
    const ownProfilePath = path === '/my-profile' && !!profile.provider_id
    const narcoticsPath = !!profile.provider_id && (path === '/narcotics' || path.startsWith('/narcotics/'))
    if (!inspectionPath && !ownProfilePath && !narcoticsPath) return redirectTo(request, '/inspections')
    return supabaseResponse
  }

  // Provider-level accounts are self-service users, but they also participate
  // in daily narcotics counts for apparatus belonging to agencies where they
  // have an active provider affiliation. Administrative narcotics routes still
  // enforce their own role checks server-side.
  if (!isAdmin) {
    if (!profile.provider_id) return redirectTo(request, '/auth/disabled')
    const ownProfilePath = path === '/my-profile'
    const narcoticsPath = path === '/narcotics' || path.startsWith('/narcotics/')
    if (!ownProfilePath && !narcoticsPath && path !== '/') return redirectTo(request, '/my-profile')
    if (path === '/') return redirectTo(request, '/my-profile')
  }

  return supabaseResponse
}

export const config = {
  matcher: [
    '/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)',
  ],
}
