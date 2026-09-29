'use server'

import { revalidatePath } from 'next/cache'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'

function value(formData: FormData, key: string) {
  const v = formData.get(key)
  return typeof v === 'string' ? v.trim() : ''
}
function checked(formData: FormData, key: string) { return formData.get(key) === 'on' }
function fail(path: string, message: string): never { redirect(`${path}?error=${encodeURIComponent(message)}`) }
function parseWarningDays(raw: string) {
  const values = raw.split(',').map((x) => Number.parseInt(x.trim(), 10)).filter((n) => Number.isInteger(n) && n >= 0)
  return Array.from(new Set(values)).sort((a,b) => b-a)
}

async function requireSystemAdmin(supabase: any, path: string) {
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) fail('/login', 'Authentication required.')
  const { data: role } = await supabase.from('user_roles').select('role').eq('user_id', user.id).eq('role', 'system_admin').maybeSingle()
  if (!role) fail(path, 'System Administrator access is required.')
}

function payload(formData: FormData) {
  const code = value(formData, 'code').toUpperCase().replace(/[^A-Z0-9_-]+/g, '_')
  const name = value(formData, 'name')
  const category = value(formData, 'category') || 'Certification'
  const renewal = value(formData, 'renewal_months')
  const warningDays = parseWarningDays(value(formData, 'warning_days'))
  return {
    code,
    name,
    category,
    description: value(formData, 'description') || null,
    renewal_months: renewal ? Number.parseInt(renewal, 10) : null,
    requires_number: checked(formData, 'requires_number'),
    requires_issue_date: checked(formData, 'requires_issue_date'),
    requires_expiration_date: checked(formData, 'requires_expiration_date'),
    requires_document: checked(formData, 'requires_document'),
    requires_verification: checked(formData, 'requires_verification'),
    warning_days: warningDays.length ? warningDays : [120,90,60,30,14,7,1],
    active: checked(formData, 'active'),
  }
}

export async function createCredentialType(formData: FormData) {
  const path = '/credentials/new'
  const data = payload(formData)
  if (!data.code || !data.name) fail(path, 'Credential name and code are required.')
  if (data.renewal_months !== null && (!Number.isInteger(data.renewal_months) || data.renewal_months <= 0)) fail(path, 'Renewal months must be a positive whole number.')
  const supabase = await createClient()
  await requireSystemAdmin(supabase, path)
  const { data: created, error } = await supabase.from('credential_types').insert(data).select('id').single()
  if (error || !created) fail(path, error?.message ?? 'Credential type could not be created.')
  revalidatePath('/credentials')
  redirect(`/credentials/${created.id}/edit?saved=1`)
}

export async function updateCredentialType(formData: FormData) {
  const id = value(formData, 'id')
  const path = `/credentials/${id}/edit`
  if (!id) fail('/credentials', 'Credential ID is missing.')
  const data = payload(formData)
  if (!data.code || !data.name) fail(path, 'Credential name and code are required.')
  const supabase = await createClient()
  await requireSystemAdmin(supabase, path)
  const { error } = await supabase.from('credential_types').update(data).eq('id', id)
  if (error) fail(path, error.message)
  revalidatePath('/credentials')
  redirect(`${path}?saved=1`)
}

export async function setCredentialTypeActive(formData: FormData) {
  const id = value(formData, 'id')
  const active = value(formData, 'active') === 'true'
  if (!id) fail('/credentials', 'Credential ID is missing.')
  const supabase = await createClient()
  await requireSystemAdmin(supabase, '/credentials')
  const { error } = await supabase.from('credential_types').update({ active }).eq('id', id)
  if (error) fail('/credentials', error.message)
  revalidatePath('/credentials')
  redirect('/credentials')
}

export async function deleteCredentialType(formData: FormData) {
  const id = value(formData, 'id')
  if (!id) fail('/credentials', 'Credential ID is missing.')
  const supabase = await createClient()
  await requireSystemAdmin(supabase, '/credentials')

  const [records, requirements, submissions] = await Promise.all([
    supabase.from('provider_credentials').select('*', { count: 'exact', head: true }).eq('credential_type_id', id),
    supabase.from('credential_requirements').select('*', { count: 'exact', head: true }).eq('credential_type_id', id),
    supabase.from('credential_submissions').select('*', { count: 'exact', head: true }).eq('credential_type_id', id),
  ])
  const used = (records.count ?? 0) + (requirements.count ?? 0) + (submissions.count ?? 0)
  if (used > 0) {
    const { error } = await supabase.from('credential_types').update({ active: false }).eq('id', id)
    if (error) fail('/credentials', error.message)
    redirect('/credentials?notice=' + encodeURIComponent('Credential is in use, so it was deactivated instead of permanently deleted.'))
  }

  const { error } = await supabase.from('credential_types').delete().eq('id', id)
  if (error) fail('/credentials', error.message)
  revalidatePath('/credentials')
  redirect('/credentials?notice=' + encodeURIComponent('Credential type deleted.'))
}
