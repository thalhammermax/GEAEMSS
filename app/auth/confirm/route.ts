import { type EmailOtpType } from '@supabase/supabase-js'
import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'

const ALLOWED_TYPES = new Set<EmailOtpType>(['invite', 'recovery'])

function safeSetupDestination(raw: string | null, origin: string) {
  const fallback = '/auth/setup-password'
  if (!raw) return fallback

  try {
    const candidate = new URL(raw, origin)

    // Never permit the auth email to become an open redirect.
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

  const supabase = await createClient()
  const { error } = await supabase.auth.verifyOtp({
    token_hash: tokenHash,
    type: rawType,
  })

  if (error) {
    return loginError(request, 'This account setup link is invalid or has expired. Ask a System Administrator to send a new email.')
  }

  const destination = safeSetupDestination(rawNext, request.nextUrl.origin)
  const url = request.nextUrl.clone()
  url.pathname = destination.split('?')[0]
  url.search = destination.includes('?') ? `?${destination.split('?').slice(1).join('?')}` : ''

  return NextResponse.redirect(url)
}
