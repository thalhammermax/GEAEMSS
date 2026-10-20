'use client'

import { useActionState } from 'react'
import { signInAction, type AuthFormState } from '@/app/auth/actions'

export function LoginForm({ notice, linkError }: { notice?: string; linkError?: string }) {
  const [state, formAction, pending] = useActionState<AuthFormState, FormData>(signInAction, null)

  return <form action={formAction} className="login-form">
    <label>Email address<input name="email" type="email" autoComplete="email" required /></label>
    <label>Password<input name="password" type="password" autoComplete="current-password" required /></label>
    {notice && !state?.error && <div className="form-success">{notice}</div>}
    {linkError && !state?.error && <div className="form-error">{linkError}</div>}
    {state?.error && <div className="form-error">{state.error}</div>}
    <button className="primary-button" disabled={pending}>{pending ? 'Signing in…' : 'Sign in'}</button>
  </form>
}
