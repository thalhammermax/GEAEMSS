'use client'

import { useActionState } from 'react'
import { setPasswordAction, type AuthFormState } from '@/app/auth/actions'

export function SetupPasswordForm({ uid, provider, ready, initialError }: { uid: string; provider: string; ready: boolean; initialError?: string }) {
  const [state, formAction, pending] = useActionState<AuthFormState, FormData>(setPasswordAction, null)
  const error = state?.error || initialError

  return <form action={formAction} className="login-form">
    <input type="hidden" name="uid" value={uid} />
    <input type="hidden" name="provider" value={provider} />
    <label>New password<input name="password" type="password" autoComplete="new-password" required minLength={8} disabled={!ready || pending}/></label>
    <label>Confirm password<input name="confirm" type="password" autoComplete="new-password" required minLength={8} disabled={!ready || pending}/></label>
    {error && <div className="form-error">{error}</div>}
    <button className="primary-button" disabled={!ready || pending}>{pending ? 'Saving…' : ready ? 'Set password' : 'Link not valid'}</button>
  </form>
}
