'use server'

import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { validateSetupIdentity } from '@/lib/setup-identity'

export type AuthFormState = { error?: string } | null

function text(formData: FormData, key: string) {
  const value = formData.get(key)
  return typeof value === 'string' ? value.trim() : ''
}

/**
 * Password sign-in performed on the server. The browser only ever talks to the
 * portal's own domain; the portal talks to Supabase. This keeps the portal
 * usable on networks (e.g. hospital Wi-Fi) that block *.supabase.co.
 */
export async function signInAction(_prev: AuthFormState, formData: FormData): Promise<AuthFormState> {
  const email = text(formData, 'email').toLowerCase()
  const password = typeof formData.get('password') === 'string' ? (formData.get('password') as string) : ''
  if (!email || !password) return { error: 'Enter your email address and password.' }

  const supabase = await createClient()
  const { error } = await supabase.auth.signInWithPassword({ email, password })
  if (error) {
    const friendly = /invalid login credentials/i.test(error.message)
      ? 'Incorrect email address or password.'
      : error.message
    return { error: friendly }
  }
  redirect('/')
}

export async function signOutAction() {
  const supabase = await createClient()
  await supabase.auth.signOut()
  redirect('/login')
}

/**
 * Completes an invite / recovery flow. The session was established server-side
 * by /auth/confirm (token_hash flow), so the password update also happens on
 * the server.
 */
export async function setPasswordAction(_prev: AuthFormState, formData: FormData): Promise<AuthFormState> {
  const password = typeof formData.get('password') === 'string' ? (formData.get('password') as string) : ''
  const confirm = typeof formData.get('confirm') === 'string' ? (formData.get('confirm') as string) : ''
  const expectedUserId = text(formData, 'uid') || null
  const expectedProviderId = text(formData, 'provider') || null

  if (password.length < 8) return { error: 'Password must be at least 8 characters.' }
  if (password !== confirm) return { error: 'Passwords do not match.' }

  const supabase = await createClient()
  const identity = await validateSetupIdentity(supabase, expectedUserId, expectedProviderId)
  if (identity.error) return { error: identity.error }

  const { error } = await supabase.auth.updateUser({ password })
  if (error) return { error: error.message }

  // End the invite/recovery session; the user signs in normally with the new password.
  await supabase.auth.signOut()
  redirect('/login?notice=' + encodeURIComponent('Password saved. Sign in with your email and new password.'))
}

