'use server'

import { revalidatePath } from 'next/cache'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'

function text(formData: FormData, key: string) {
  const value = formData.get(key)
  return typeof value === 'string' ? value.trim() : ''
}
function checked(formData: FormData, key: string) { return formData.get(key) === 'on' }
function fail(path: string, message: string): never { redirect(`${path}${path.includes('?') ? '&' : '?'}error=${encodeURIComponent(message)}`) }

export async function saveNarcoticsCount(formData: FormData) {
  const vehicleId = text(formData, 'vehicle_id')
  const countId = text(formData, 'count_id') || null
  const countDate = text(formData, 'count_date')
  const mode = text(formData, 'mode') === 'submit' ? 'submit' : 'draft'
  const path = `/narcotics/count/${vehicleId}`
  if (!vehicleId || !countDate) fail('/narcotics', 'Vehicle and count date are required.')

  const itemIds = formData.getAll('item_id').filter((v): v is string => typeof v === 'string')
  const lines = itemIds.map((id) => {
    const raw = text(formData, `actual_${id}`)
    return {
      item_id: id,
      actual_quantity: raw === '' ? null : Number(raw),
      notes: text(formData, `notes_${id}`),
    }
  })
  if (lines.some((line) => line.actual_quantity !== null && (!Number.isFinite(line.actual_quantity) || Number(line.actual_quantity) < 0))) {
    fail(path, 'Narcotics quantities must be non-negative numbers.')
  }

  const supabase = await createClient()
  const { data, error } = await supabase.rpc('save_narcotics_count', {
    p_count_id: countId,
    p_vehicle_id: vehicleId,
    p_count_date: countDate,
    p_notes: text(formData, 'notes'),
    p_mode: mode,
    p_signature_name: text(formData, 'signature_name'),
    p_attestation: checked(formData, 'attestation'),
    p_lines: lines,
  })
  if (error) fail(path, error.message)

  const id = String(data)
  revalidatePath('/narcotics')
  revalidatePath(path)
  revalidatePath(`/narcotics/${id}`)
  redirect(mode === 'submit' ? `/narcotics/${id}?submitted=1` : `${path}?saved=1`)
}

export async function saveNarcoticsAgencySettings(formData: FormData) {
  const agencyId = text(formData, 'agency_id')
  if (!agencyId) fail('/narcotics/settings', 'Agency is required.')
  const reportHour = Number(text(formData, 'report_hour'))
  if (!Number.isInteger(reportHour) || reportHour < 0 || reportHour > 23) fail('/narcotics/settings', 'Report hour must be between 0 and 23.')

  const supabase = await createClient()
  const { error } = await supabase.from('narcotics_agency_settings').upsert({
    agency_id: agencyId,
    enabled: checked(formData, 'enabled'),
    timezone: text(formData, 'timezone') || 'America/Chicago',
    report_hour: reportHour,
    send_incomplete_report: checked(formData, 'send_incomplete_report'),
    default_template_id: text(formData, 'default_template_id') || null,
    signature_attestation: text(formData, 'signature_attestation'),
  }, { onConflict: 'agency_id' })
  if (error) fail('/narcotics/settings', error.message)
  revalidatePath('/narcotics/settings')
  revalidatePath('/narcotics')
  redirect('/narcotics/settings?notice=' + encodeURIComponent('Agency narcotics settings saved.'))
}

export async function createNarcoticsTemplate(formData: FormData) {
  const scopeType = text(formData, 'scope_type') === 'agency' ? 'agency' : 'system'
  const agencyId = scopeType === 'agency' ? text(formData, 'agency_id') : ''
  const name = text(formData, 'name')
  if (!name) fail('/narcotics/templates/new', 'Template name is required.')
  if (scopeType === 'agency' && !agencyId) fail('/narcotics/templates/new', 'Agency is required for an agency template.')

  const supabase = await createClient()
  const { data, error } = await supabase.from('narcotics_count_templates').insert({
    name,
    description: text(formData, 'description') || null,
    scope_type: scopeType,
    agency_id: agencyId || null,
    active: true,
  }).select('id').single()
  if (error) fail('/narcotics/templates/new', error.message)
  revalidatePath('/narcotics/settings')
  redirect(`/narcotics/templates/${data.id}?notice=${encodeURIComponent('Template created. Add the controlled substances that should be counted.')}`)
}

export async function updateNarcoticsTemplate(formData: FormData) {
  const id = text(formData, 'template_id')
  if (!id) fail('/narcotics/settings', 'Template is required.')
  const supabase = await createClient()
  const { error } = await supabase.from('narcotics_count_templates').update({
    name: text(formData, 'name'),
    description: text(formData, 'description') || null,
    active: checked(formData, 'active'),
  }).eq('id', id)
  if (error) fail(`/narcotics/templates/${id}`, error.message)
  revalidatePath('/narcotics/settings')
  revalidatePath(`/narcotics/templates/${id}`)
  redirect(`/narcotics/templates/${id}?notice=${encodeURIComponent('Template updated.')}`)
}

export async function addNarcoticsTemplateItem(formData: FormData) {
  const templateId = text(formData, 'template_id')
  if (!templateId) fail('/narcotics/settings', 'Template is required.')
  const medicationName = text(formData, 'medication_name')
  const expected = Number(text(formData, 'expected_quantity'))
  if (!medicationName) fail(`/narcotics/templates/${templateId}`, 'Medication name is required.')
  if (!Number.isFinite(expected) || expected < 0) fail(`/narcotics/templates/${templateId}`, 'Expected quantity must be a non-negative number.')
  const sortOrder = Number(text(formData, 'sort_order') || '100')

  const supabase = await createClient()
  const { error } = await supabase.from('narcotics_count_template_items').insert({
    template_id: templateId,
    medication_name: medicationName,
    concentration: text(formData, 'concentration') || null,
    dosage_form: text(formData, 'dosage_form') || null,
    controlled_substance_schedule: text(formData, 'controlled_substance_schedule') || null,
    unit_label: text(formData, 'unit_label') || 'unit',
    expected_quantity: expected,
    sort_order: Number.isFinite(sortOrder) ? sortOrder : 100,
    active: true,
  })
  if (error) fail(`/narcotics/templates/${templateId}`, error.message)
  revalidatePath(`/narcotics/templates/${templateId}`)
  redirect(`/narcotics/templates/${templateId}?notice=${encodeURIComponent('Count item added.')}`)
}

export async function deleteNarcoticsTemplateItem(formData: FormData) {
  const templateId = text(formData, 'template_id')
  const itemId = text(formData, 'item_id')
  if (!templateId || !itemId) fail('/narcotics/settings', 'Template item is required.')
  const supabase = await createClient()
  const { error } = await supabase.from('narcotics_count_template_items').delete().eq('id', itemId).eq('template_id', templateId)
  if (error) fail(`/narcotics/templates/${templateId}`, error.message)
  revalidatePath(`/narcotics/templates/${templateId}`)
  redirect(`/narcotics/templates/${templateId}?notice=${encodeURIComponent('Count item removed.')}`)
}
