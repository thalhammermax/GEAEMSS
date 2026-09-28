'use server'

import { revalidatePath } from 'next/cache'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import type { EntityType, FieldType } from '@/lib/record-fields'

function textValue(formData: FormData, key: string) {
  const value = formData.get(key)
  return typeof value === 'string' ? value.trim() : ''
}

function entityValue(formData: FormData): EntityType {
  const value = textValue(formData, 'entity_type')
  if (value === 'provider' || value === 'agency' || value === 'vehicle') return value
  return 'provider'
}

function fail(entity: EntityType, message: string): never {
  redirect(`/administration/fields?entity=${entity}&error=${encodeURIComponent(message)}`)
}

function slug(label: string) {
  return label.toLowerCase().trim().replace(/[^a-z0-9]+/g, '_').replace(/^_+|_+$/g, '').slice(0, 45)
}

export async function updateFieldDefinition(formData: FormData) {
  const id = textValue(formData, 'id')
  const entity = entityValue(formData)
  if (!id) fail(entity, 'Field ID is missing.')

  const supabase = await createClient()
  const { data: current, error: fetchError } = await supabase
    .from('record_field_definitions')
    .select('system_locked')
    .eq('id', id)
    .maybeSingle()
  if (fetchError || !current) fail(entity, fetchError?.message ?? 'Field not found.')

  const enabled = current.system_locked ? true : textValue(formData, 'enabled') === 'on'
  const required = current.system_locked ? true : textValue(formData, 'required') === 'on'
  const sortOrder = Number(textValue(formData, 'sort_order') || '100')

  const { error } = await supabase.from('record_field_definitions').update({
    enabled,
    required,
    sort_order: Number.isFinite(sortOrder) ? sortOrder : 100,
  }).eq('id', id)

  if (error) fail(entity, error.message)
  revalidatePath('/administration/fields')
  revalidatePath('/personnel')
  revalidatePath('/fleet')
  redirect(`/administration/fields?entity=${entity}&saved=1`)
}

export async function createCustomField(formData: FormData) {
  const entity = entityValue(formData)
  const label = textValue(formData, 'label')
  const fieldType = textValue(formData, 'field_type') as FieldType
  const allowed: FieldType[] = ['text','textarea','number','date','boolean','email','phone','url','select','multiselect']
  if (!label) fail(entity, 'Field label is required.')
  if (!allowed.includes(fieldType)) fail(entity, 'Select a valid field type.')

  const optionLines = textValue(formData, 'options')
    .split('\n')
    .map((item) => item.trim())
    .filter(Boolean)
  if ((fieldType === 'select' || fieldType === 'multiselect') && optionLines.length === 0) {
    fail(entity, 'Select fields need at least one option.')
  }

  const baseKey = `custom_${slug(label) || 'field'}`
  const supabase = await createClient()

  let fieldKey = baseKey
  for (let attempt = 0; attempt < 20; attempt += 1) {
    const { data: existing } = await supabase
      .from('record_field_definitions')
      .select('id')
      .eq('entity_type', entity)
      .eq('field_key', fieldKey)
      .maybeSingle()
    if (!existing) break
    fieldKey = `${baseKey}_${attempt + 2}`
  }

  const sortOrder = Number(textValue(formData, 'sort_order') || '500')
  const { error } = await supabase.from('record_field_definitions').insert({
    entity_type: entity,
    field_key: fieldKey,
    label,
    field_type: fieldType,
    source_type: 'custom',
    builtin_column: null,
    field_group: textValue(formData, 'field_group') || 'Additional Information',
    help_text: textValue(formData, 'help_text') || null,
    placeholder: textValue(formData, 'placeholder') || null,
    options: optionLines,
    enabled: textValue(formData, 'enabled') === 'on',
    required: textValue(formData, 'required') === 'on',
    system_locked: false,
    sort_order: Number.isFinite(sortOrder) ? sortOrder : 500,
  })

  if (error) fail(entity, error.message)
  revalidatePath('/administration/fields')
  redirect(`/administration/fields?entity=${entity}&saved=1`)
}
