'use server'

import { revalidatePath } from 'next/cache'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'

function textValue(formData: FormData, key: string) {
  const value = formData.get(key)
  return typeof value === 'string' ? value.trim() : ''
}

function fail(path: string, message: string): never {
  redirect(`${path}${path.includes('?') ? '&' : '?'}error=${encodeURIComponent(message)}`)
}

export async function saveInspection(formData: FormData) {
  const inspectionId = textValue(formData, 'inspection_id') || null
  const vehicleId = textValue(formData, 'vehicle_id')
  const formVersionId = textValue(formData, 'form_version_id')
  const mode = textValue(formData, 'mode') === 'submit' ? 'submit' : 'draft'
  const returnPath = inspectionId ? `/inspections/${inspectionId}` : `/inspections/new?vehicle=${encodeURIComponent(vehicleId)}`

  if (!vehicleId || !formVersionId) fail('/inspections', 'Vehicle and inspection form are required.')

  const inspectionDate = textValue(formData, 'inspection_date')
  if (!inspectionDate) fail(returnPath, 'Inspection date is required.')

  const odometerRaw = textValue(formData, 'odometer')
  let odometer: number | null = null
  if (odometerRaw) {
    const parsed = Number(odometerRaw)
    if (!Number.isInteger(parsed) || parsed < 0) fail(returnPath, 'Odometer must be a non-negative whole number.')
    odometer = parsed
  }

  const itemIds = formData.getAll('form_item_id').filter((value): value is string => typeof value === 'string')
  const responses = itemIds.map((id) => ({
    form_item_id: id,
    status: textValue(formData, `status_${id}`),
    observed_value: textValue(formData, `observed_${id}`),
    notes: textValue(formData, `notes_${id}`),
  }))

  const supabase = await createClient()
  const { data, error } = await supabase.rpc('save_digital_vehicle_inspection', {
    p_inspection_id: inspectionId,
    p_vehicle_id: vehicleId,
    p_form_version_id: formVersionId,
    p_inspection_date: inspectionDate,
    p_inspector_name: textValue(formData, 'inspector_name'),
    p_inspector_organization: textValue(formData, 'inspector_organization'),
    p_inspection_location: textValue(formData, 'inspection_location'),
    p_odometer: odometer,
    p_notes: textValue(formData, 'inspection_notes'),
    p_mode: mode,
    p_final_result: textValue(formData, 'final_result'),
    p_responses: responses,
  })

  if (error) fail(returnPath, error.message)
  const id = String(data)

  revalidatePath('/inspections')
  revalidatePath(`/inspections/${id}`)
  revalidatePath('/dashboard')
  revalidatePath('/fleet')
  revalidatePath(`/fleet/${vehicleId}`)
  redirect(`/inspections/${id}?${mode === 'submit' ? 'submitted=1' : 'saved=1'}`)
}
