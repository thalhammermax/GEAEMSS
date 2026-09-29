'use server'

import { revalidatePath } from 'next/cache'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { builtinFieldMap, fetchFieldDefinitions, isEnabled, isRequired, saveCustomFieldValues, validateCustomFieldValues } from '@/lib/record-fields'

function textValue(formData: FormData, key: string) {
  const value = formData.get(key)
  return typeof value === 'string' ? value.trim() : ''
}
function nullable(value: string) { return value || null }
function fail(path: string, message: string): never { redirect(`${path}?error=${encodeURIComponent(message)}`) }

async function vehiclePayload(supabase: any, formData: FormData, path: string) {
  const { fields, error } = await fetchFieldDefinitions(supabase, 'vehicle')
  if (error) fail(path, error.message)
  const map = builtinFieldMap(fields)
  const payload: Record<string, string | number | boolean | null> = {}

  for (const key of ['agency_id','vehicle_type_id','vehicle_status_id','unit_number','fleet_number','vin','make','model','license_plate','license_plate_state','in_service_date','retired_date','notes']) {
    if (!isEnabled(map, key)) continue
    const value = textValue(formData, key)
    if (isRequired(map, key, key === 'agency_id') && !value) fail(path, `${map.get(key)?.label ?? key} is required.`)
    payload[key] = nullable(value)
  }

  if (isEnabled(map, 'year')) {
    const value = textValue(formData, 'year')
    if (isRequired(map, 'year') && !value) fail(path, `${map.get('year')?.label ?? 'Year'} is required.`)
    if (value) {
      const parsed = Number(value)
      if (!Number.isInteger(parsed) || parsed < 1900 || parsed > 2200) fail(path, 'Year must be a valid four-digit year.')
      payload.year = parsed
    } else payload.year = null
  }

  payload.narcotics_count_required = formData.get('narcotics_count_required') === 'on'
  const narcoticsTemplateId = textValue(formData, 'narcotics_template_id')
  payload.narcotics_template_id = narcoticsTemplateId || null

  return payload
}

export async function createVehicle(formData: FormData) {
  const supabase = await createClient()
  const customValidation = await validateCustomFieldValues(supabase, 'vehicle', formData)
  if (customValidation) fail('/fleet/new', customValidation)
  const payload = await vehiclePayload(supabase, formData, '/fleet/new')

  const { data, error } = await supabase.from('vehicles').insert({ ...payload, active: true }).select('id').single()
  if (error) fail('/fleet/new', error.message)

  const customError = await saveCustomFieldValues(supabase, 'vehicle', data.id, formData)
  if (customError) fail(`/fleet/${data.id}`, `Vehicle was created, but custom fields could not be saved: ${customError}`)

  revalidatePath('/fleet')
  revalidatePath('/dashboard')
  redirect(`/fleet/${data.id}?saved=1`)
}

export async function updateVehicle(formData: FormData) {
  const id = textValue(formData, 'id')
  if (!id) fail('/fleet', 'Vehicle ID is required.')
  const path = `/fleet/${id}`
  const supabase = await createClient()

  const customValidation = await validateCustomFieldValues(supabase, 'vehicle', formData)
  if (customValidation) fail(path, customValidation)
  const payload = await vehiclePayload(supabase, formData, path)

  const { error } = await supabase.from('vehicles').update(payload).eq('id', id)
  if (error) fail(path, error.message)
  const customError = await saveCustomFieldValues(supabase, 'vehicle', id, formData)
  if (customError) fail(path, customError)

  revalidatePath('/fleet')
  revalidatePath(path)
  revalidatePath('/dashboard')
  redirect(`${path}?saved=1`)
}

export async function setVehicleActive(formData: FormData) {
  const id = textValue(formData, 'id')
  const active = textValue(formData, 'active') === 'true'
  if (!id) fail('/fleet', 'Vehicle ID is required.')
  const supabase = await createClient()
  const { error } = await supabase.from('vehicles').update({ active }).eq('id', id)
  if (error) fail(`/fleet/${id}`, error.message)
  revalidatePath('/fleet')
  revalidatePath(`/fleet/${id}`)
  revalidatePath('/dashboard')
  redirect(`/fleet/${id}?saved=1`)
}
