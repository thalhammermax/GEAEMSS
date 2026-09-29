'use server'

import { revalidatePath } from 'next/cache'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { builtinFieldMap, fetchFieldDefinitions, isEnabled, isRequired, saveCustomFieldValues, validateCustomFieldValues } from '@/lib/record-fields'
import { inviteProviderAccount } from '@/lib/user-accounts'
import { createAdminClient } from '@/lib/supabase/admin'

function textValue(formData: FormData, key: string) {
  const value = formData.get(key)
  return typeof value === 'string' ? value.trim() : ''
}

function nullable(value: string) { return value || null }
function fail(path: string, message: string): never { redirect(`${path}?error=${encodeURIComponent(message)}`) }

async function providerPayload(supabase: any, formData: FormData, path: string) {
  const { fields, error } = await fetchFieldDefinitions(supabase, 'provider')
  if (error) fail(path, error.message)
  const fieldMap = builtinFieldMap(fields)
  const payload: Record<string, string | null> = {}

  const textFields = ['first_name','middle_name','last_name','preferred_name','provider_number','email','phone','notes']
  const nullableFields = new Set(['middle_name','preferred_name','provider_number','email','phone','notes'])
  for (const key of textFields) {
    if (!isEnabled(fieldMap, key)) continue
    const value = textValue(formData, key)
    if (isRequired(fieldMap, key, key === 'first_name' || key === 'last_name') && !value) fail(path, `${fieldMap.get(key)?.label ?? key} is required.`)
    payload[key] = nullableFields.has(key) ? nullable(value) : value
  }

  for (const key of ['provider_level_id','provider_status_id','system_entry_date']) {
    if (!isEnabled(fieldMap, key)) continue
    const value = textValue(formData, key)
    if (isRequired(fieldMap, key) && !value) fail(path, `${fieldMap.get(key)?.label ?? key} is required.`)
    payload[key] = nullable(value)
  }
  return payload
}

export async function createProvider(formData: FormData) {
  const agencyId = textValue(formData, 'agency_id')
  if (!agencyId) fail('/personnel/new', 'Primary agency is required.')

  const supabase = await createClient()
  const customValidation = await validateCustomFieldValues(supabase, 'provider', formData)
  if (customValidation) fail('/personnel/new', customValidation)
  const payload = await providerPayload(supabase, formData, '/personnel/new')
  const sendInvite = formData.get('send_account_invite') === 'on'
  if (sendInvite && !payload.email) fail('/personnel/new', 'An email address is required when sending a portal account setup link.')

  const { data: providerId, error: providerError } = await supabase.rpc('create_provider_with_primary_agency', {
    p_agency_id: agencyId,
    p_provider: payload,
    p_affiliation: {
      employee_id: nullable(textValue(formData, 'employee_id')),
      agency_provider_level_id: nullable(textValue(formData, 'agency_provider_level_id')),
      start_date: nullable(textValue(formData, 'start_date')),
    },
  })
  if (providerError || !providerId) fail('/personnel/new', providerError?.message ?? 'Provider could not be created.')

  const customError = await saveCustomFieldValues(supabase, 'provider', providerId, formData)
  if (customError) fail(`/personnel/${providerId}/edit`, `Provider was created, but custom fields could not be saved: ${customError}`)

  let inviteResult = ''
  if (sendInvite) {
    try {
      await inviteProviderAccount(providerId)
      inviteResult = '&inviteSent=1'
    } catch (error: any) {
      inviteResult = `&inviteError=${encodeURIComponent(error?.message ?? 'The provider was created, but the account setup email could not be sent.')}`
    }
  }

  revalidatePath('/personnel')
  revalidatePath('/dashboard')
  revalidatePath('/administration/agencies')
  revalidatePath('/administration/users')
  redirect(`/personnel/${providerId}?saved=1${inviteResult}`)
}

export async function updateProvider(formData: FormData) {
  const id = textValue(formData, 'id')
  if (!id) fail('/personnel', 'Provider ID is required.')
  const path = `/personnel/${id}/edit`
  const supabase = await createClient()

  const customValidation = await validateCustomFieldValues(supabase, 'provider', formData)
  if (customValidation) fail(path, customValidation)
  const payload = await providerPayload(supabase, formData, path)
  const { data: currentProvider, error: currentError } = await supabase.from('providers').select('email').eq('id', id).maybeSingle()
  if (currentError || !currentProvider) fail(path, currentError?.message ?? 'Provider could not be loaded.')

  const { error } = await supabase.from('providers').update(payload).eq('id', id)
  if (error) fail(path, error.message)

  if (Object.prototype.hasOwnProperty.call(payload, 'email') && payload.email !== currentProvider.email) {
    try {
      const admin = createAdminClient()
      const { data: linkedProfile, error: linkedError } = await admin.from('profiles').select('id').eq('provider_id', id).maybeSingle()
      if (linkedError) throw linkedError
      if (linkedProfile) {
        if (!payload.email) throw new Error('A provider with a portal account must retain an email address because the email is the login username.')
        const { error: authError } = await admin.auth.admin.updateUserById(linkedProfile.id, { email: payload.email })
        if (authError) throw authError
      }
    } catch (syncError: any) {
      await supabase.from('providers').update({ email: currentProvider.email }).eq('id', id)
      fail(path, `Email was not changed because the linked login could not be updated: ${syncError?.message ?? 'Unknown error'}`)
    }
  }

  const customError = await saveCustomFieldValues(supabase, 'provider', id, formData)
  if (customError) fail(path, customError)

  revalidatePath('/personnel')
  revalidatePath(`/personnel/${id}`)
  revalidatePath('/dashboard')
  redirect(`/personnel/${id}?saved=1`)
}

export async function addAffiliation(formData: FormData) {
  const providerId = textValue(formData, 'provider_id')
  const agencyId = textValue(formData, 'agency_id')
  if (!providerId || !agencyId) fail(`/personnel/${providerId || ''}`, 'Provider and agency are required.')
  let makePrimary = textValue(formData, 'is_primary') === 'on'
  const supabase = await createClient()

  const { count: activeCount } = await supabase.from('provider_agencies').select('*', { count: 'exact', head: true }).eq('provider_id', providerId).eq('active', true)
  if ((activeCount ?? 0) === 0) makePrimary = true

  if (makePrimary) {
    const { error } = await supabase.from('provider_agencies').update({ is_primary: false }).eq('provider_id', providerId).eq('active', true)
    if (error) fail(`/personnel/${providerId}`, error.message)
  }

  const { error } = await supabase.from('provider_agencies').insert({
    provider_id: providerId,
    agency_id: agencyId,
    employee_id: nullable(textValue(formData, 'employee_id')),
    agency_provider_level_id: nullable(textValue(formData, 'agency_provider_level_id')),
    start_date: nullable(textValue(formData, 'start_date')),
    is_primary: makePrimary,
    active: true,
  })

  if (error) fail(`/personnel/${providerId}`, error.message)
  revalidatePath(`/personnel/${providerId}`)
  revalidatePath('/personnel')
  revalidatePath('/administration/agencies')
  redirect(`/personnel/${providerId}?saved=1`)
}

export async function setPrimaryAffiliation(formData: FormData) {
  const providerId = textValue(formData, 'provider_id')
  const affiliationId = textValue(formData, 'affiliation_id')
  if (!providerId || !affiliationId) fail('/personnel', 'Affiliation details are missing.')
  const supabase = await createClient()
  const { error: clearError } = await supabase.from('provider_agencies').update({ is_primary: false }).eq('provider_id', providerId).eq('active', true)
  if (clearError) fail(`/personnel/${providerId}`, clearError.message)
  const { error } = await supabase.from('provider_agencies').update({ is_primary: true }).eq('id', affiliationId)
  if (error) fail(`/personnel/${providerId}`, error.message)
  revalidatePath(`/personnel/${providerId}`)
  redirect(`/personnel/${providerId}?saved=1`)
}

export async function endAffiliation(formData: FormData) {
  const providerId = textValue(formData, 'provider_id')
  const affiliationId = textValue(formData, 'affiliation_id')
  if (!providerId || !affiliationId) fail('/personnel', 'Affiliation details are missing.')
  const supabase = await createClient()
  const { data: ending } = await supabase.from('provider_agencies').select('is_primary').eq('id', affiliationId).maybeSingle()
  const { error } = await supabase.from('provider_agencies').update({
    active: false,
    is_primary: false,
    end_date: new Date().toISOString().slice(0, 10),
  }).eq('id', affiliationId)
  if (error) fail(`/personnel/${providerId}`, error.message)
  if (ending?.is_primary) {
    const { data: replacement } = await supabase.from('provider_agencies').select('id').eq('provider_id', providerId).eq('active', true).order('created_at').limit(1).maybeSingle()
    if (replacement) await supabase.from('provider_agencies').update({ is_primary: true }).eq('id', replacement.id)
  }
  revalidatePath(`/personnel/${providerId}`)
  revalidatePath('/personnel')
  revalidatePath('/administration/agencies')
  redirect(`/personnel/${providerId}?saved=1`)
}
