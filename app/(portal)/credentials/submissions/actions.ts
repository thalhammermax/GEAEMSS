'use server'

import { revalidatePath } from 'next/cache'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'

function value(formData: FormData, key: string) {
  const v = formData.get(key)
  return typeof v === 'string' ? v.trim() : ''
}
function fail(path: string, message: string): never { redirect(`${path}?error=${encodeURIComponent(message)}`) }

export async function approveCredentialSubmission(formData: FormData) {
  const id = value(formData, 'id')
  if (!id) fail('/credentials/submissions', 'Submission ID is missing.')
  const notes = value(formData, 'review_notes') || null
  const supabase = await createClient()
  const { error } = await supabase.rpc('approve_credential_submission', { p_submission_id: id, p_review_notes: notes })
  if (error) fail(`/credentials/submissions/${id}`, error.message)
  revalidatePath('/credentials/submissions')
  revalidatePath('/credentials')
  revalidatePath('/dashboard')
  revalidatePath('/personnel')
  redirect('/credentials/submissions?notice=' + encodeURIComponent('Credential approved and added to the provider record.'))
}

export async function requestCredentialChanges(formData: FormData) {
  const id = value(formData, 'id')
  const notes = value(formData, 'review_notes')
  if (!id) fail('/credentials/submissions', 'Submission ID is missing.')
  if (!notes) fail(`/credentials/submissions/${id}`, 'Explain what the provider needs to change.')
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) fail('/login', 'Please sign in again.')
  const { error } = await supabase.from('credential_submissions').update({
    status: 'changes_requested', reviewed_by: user.id, reviewed_at: new Date().toISOString(), review_notes: notes,
  }).eq('id', id).in('status', ['pending', 'changes_requested'])
  if (error) fail(`/credentials/submissions/${id}`, error.message)
  revalidatePath('/credentials/submissions')
  revalidatePath('/dashboard')
  redirect('/credentials/submissions?notice=' + encodeURIComponent('Changes requested from provider.'))
}

export async function rejectCredentialSubmission(formData: FormData) {
  const id = value(formData, 'id')
  const notes = value(formData, 'review_notes')
  if (!id) fail('/credentials/submissions', 'Submission ID is missing.')
  if (!notes) fail(`/credentials/submissions/${id}`, 'A rejection reason is required.')
  const supabase = await createClient()
  const { error } = await supabase.rpc('reject_credential_submission', { p_submission_id: id, p_review_notes: notes })
  if (error) fail(`/credentials/submissions/${id}`, error.message)
  revalidatePath('/credentials/submissions')
  revalidatePath('/dashboard')
  redirect('/credentials/submissions?notice=' + encodeURIComponent('Credential submission rejected.'))
}
