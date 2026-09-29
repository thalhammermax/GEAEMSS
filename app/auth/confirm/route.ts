import { createServerClient } from '@supabase/ssr'
import { type EmailOtpType } from '@supabase/supabase-js'
import { NextRequest, NextResponse } from 'next/server'

const ALLOWED_TYPES = new Set<EmailOtpType>(['invite', 'recovery'])

function safeSetupDestination(raw: string | null, origin: string) {
  const fallback = '/auth/setup-password'
  if (!raw) return fallback

  try {
    const candidate = new URL(raw, origin)

    // Never permit an auth email to become an open redirect.
    if (candidate.origin !== origin) return fallback
    if (candidate.pathname !== '/auth/setup-password') return fallback

    return `${candidate.pathname}${candidate.search}`
  } catch {
    return fallback
  }
}

function loginError(request: NextRequest, message: string) {
  const url = request.nextUrl.clone()
  url.pathname = '/login'
  url.search = ''
  url.searchParams.set('error', message)
  return NextResponse.redirect(url)
}

export async function GET(request: NextRequest) {
  const tokenHash = request.nextUrl.searchParams.get('token_hash')
  const rawType = request.nextUrl.searchParams.get('type') as EmailOtpType | null
  const rawNext = request.nextUrl.searchParams.get('next')
    ?? request.nextUrl.searchParams.get('redirect_to')

  if (!tokenHash || !rawType || !ALLOWED_TYPES.has(rawType)) {
    return loginError(request, 'This account setup link is invalid. Ask a System Administrator to send a new email.')
  }

  // Collect every cookie Supabase wants to set while verifying the token.
  // We construct the redirect only AFTER verifyOtp succeeds so the redirect
  // can be bound to the exact user Supabase verified, then attach the cookies
  // to that same final response.
  let pendingCookies: Array<{
    name: string
    value: string
    options?: Parameters<NextResponse['cookies']['set']>[2]
  }> = []

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!,
    {
      cookies: {
        getAll() {
          return request.cookies.getAll()
        },
        setAll(cookiesToSet) {
          pendingCookies = cookiesToSet
          cookiesToSet.forEach(({ name, value }) => request.cookies.set(name, value))
        },
      },
    },
  )

  const { data, error } = await supabase.auth.verifyOtp({
    token_hash: tokenHash,
    type: rawType,
  })

  if (error || !data.session || !data.user) {
    return loginError(request, 'This account setup link is invalid or has expired. Ask a System Administrator to send a new email.')
  }

  const destination = safeSetupDestination(rawNext, request.nextUrl.origin)
  const redirectUrl = new URL(destination, request.nextUrl.origin)

  // Supabase is the authority for the account identity. Never depend on the
  // nested RedirectTo query string to preserve a uid/provider parameter.
  redirectUrl.searchParams.set('uid', data.user.id)

  const response = NextResponse.redirect(redirectUrl)
  pendingCookies.forEach(({ name, value, options }) => {
    response.cookies.set(name, value, options)
  })

  return response
}
