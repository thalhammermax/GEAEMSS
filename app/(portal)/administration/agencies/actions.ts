'use server'

import { revalidatePath } from 'next/cache'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { builtinFieldMap, fetchFieldDefinitions, isEnabled, isRequired, saveCustomFieldValues, validateCustomFieldValues } from '@/lib/record-fields'

function textValue(formData: FormData, key: string) {
  const value = formData.get(key)
  return typeof value === 'string' ? value.trim() : ''
}

function fail(path: string, message: string): never {
  redirect(`${path}?error=${encodeURIComponent(message)}`)
}

async function agencyPayload(supabase: any, formData: FormData, path: string) {
  const { fields, error } = await fetchFieldDefinitions(supabase, 'agency')
  if (error) fail(path, error.message)
  const map = builtinFieldMap(fields)
  const payload: Record<string, string | null> = {}

  for (const key of ['name','short_name']) {
    if (!isEnabled(map, key)) continue
    const value = textValue(formData, key)
    if (isRequired(map, key, key === 'name') && !value) fail(path, `${map.get(key)?.label ?? key} is required.`)
    payload[key] = key === 'short_name' ? (value || null) : value
  }
  return payload
}

export async function createAgency(formData: FormData) {
  const supabase = await createClient()
  const customValidation = await validateCustomFieldValues(supabase, 'agency', formData)
  if (customValidation) fail('/administration/agencies/new', customValidation)
  const payload = await agencyPayload(supabase, formData, '/administration/agencies/new')

  const { data, error } = await supabase
    .from('agencies')
    .insert({ ...payload, active: true })
    .select('id')
    .single()

  if (error) fail('/administration/agencies/new', error.message)
  const customError = await saveCustomFieldValues(supabase, 'agency', data.id, formData)
  if (customError) {
    await supabase.from('agencies').delete().eq('id', data.id)
    fail('/administration/agencies/new', customError)
  }

  revalidatePath('/administration')
  revalidatePath('/administration/agencies')
  redirect(`/administration/agencies/${data.id}?saved=1`)
}

export async function updateAgency(formData: FormData) {
  const id = textValue(formData, 'id')
  if (!id) fail('/administration/agencies', 'Agency ID is required.')
  const path = `/administration/agencies/${id}`
  const supabase = await createClient()

  const customValidation = await validateCustomFieldValues(supabase, 'agency', formData)
  if (customValidation) fail(path, customValidation)
  const payload = await agencyPayload(supabase, formData, path)

  const { error } = await supabase.from('agencies').update(payload).eq('id', id)
  if (error) fail(path, error.message)
  const customError = await saveCustomFieldValues(supabase, 'agency', id, formData)
  if (customError) fail(path, customError)

  revalidatePath('/administration')
  revalidatePath('/administration/agencies')
  revalidatePath(path)
  redirect(`${path}?saved=1`)
}

export async function setAgencyActive(formData: FormData) {
  const id = textValue(formData, 'id')
  const active = textValue(formData, 'active') === 'true'
  if (!id) fail('/administration/agencies', 'Agency ID is required.')

  const supabase = await createClient()
  const { error } = await supabase.from('agencies').update({ active }).eq('id', id)
  if (error) fail(`/administration/agencies/${id}`, error.message)

  revalidatePath('/administration')
  revalidatePath('/administration/agencies')
  revalidatePath(`/administration/agencies/${id}`)
  redirect(`/administration/agencies/${id}?saved=1`)
}
