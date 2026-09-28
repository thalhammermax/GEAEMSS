export type EntityType = 'provider' | 'agency' | 'vehicle'
export type FieldType = 'text' | 'textarea' | 'number' | 'date' | 'boolean' | 'email' | 'phone' | 'url' | 'select' | 'multiselect'

export type RecordFieldDefinition = {
  id: string
  entity_type: EntityType
  field_key: string
  label: string
  field_type: FieldType
  source_type: 'builtin' | 'custom'
  builtin_column: string | null
  field_group: string
  help_text: string | null
  placeholder: string | null
  options: unknown
  enabled: boolean
  required: boolean
  system_locked: boolean
  sort_order: number
}

export function optionList(field: RecordFieldDefinition): string[] {
  return Array.isArray(field.options)
    ? field.options.filter((value): value is string => typeof value === 'string')
    : []
}

export function fieldName(fieldId: string) {
  return `custom_${fieldId}`
}

export function builtinFieldMap(fields: RecordFieldDefinition[]) {
  return new Map(fields.filter((field) => field.source_type === 'builtin').map((field) => [field.field_key, field]))
}

export function isEnabled(map: Map<string, RecordFieldDefinition>, key: string) {
  return map.get(key)?.enabled ?? true
}

export function isRequired(map: Map<string, RecordFieldDefinition>, key: string, fallback = false) {
  return map.get(key)?.required ?? fallback
}

export async function fetchFieldDefinitions(supabase: any, entityType: EntityType) {
  const { data, error } = await supabase
    .from('record_field_definitions')
    .select('*')
    .eq('entity_type', entityType)
    .order('sort_order')
    .order('label')

  return {
    fields: (data ?? []) as RecordFieldDefinition[],
    error,
  }
}

export async function fetchCustomFieldValues(supabase: any, entityId: string) {
  const { data, error } = await supabase
    .from('record_custom_field_values')
    .select('field_definition_id, value')
    .eq('entity_id', entityId)

  const values = new Map<string, unknown>()
  for (const row of data ?? []) values.set(row.field_definition_id, row.value)
  return { values, error }
}


function readCustomFieldValue(field: RecordFieldDefinition, formData: FormData) {
  const name = fieldName(field.id)
  if (field.field_type === 'boolean') return { value: formData.get(name) === 'on', hasValue: true, error: null as string | null }
  if (field.field_type === 'multiselect') {
    const list = formData.getAll(name).filter((item): item is string => typeof item === 'string' && item.trim() !== '')
    return { value: list, hasValue: list.length > 0, error: null as string | null }
  }

  const raw = formData.get(name)
  const text = typeof raw === 'string' ? raw.trim() : ''
  const hasValue = text !== ''
  if (field.field_type === 'number') {
    const parsed = Number(text)
    if (hasValue && !Number.isFinite(parsed)) return { value: null, hasValue, error: `${field.label} must be a valid number.` }
    return { value: parsed, hasValue, error: null as string | null }
  }
  return { value: text, hasValue, error: null as string | null }
}

export async function validateCustomFieldValues(
  supabase: any,
  entityType: EntityType,
  formData: FormData,
): Promise<string | null> {
  const { fields, error } = await fetchFieldDefinitions(supabase, entityType)
  if (error) return error.message
  for (const field of fields.filter((item) => item.source_type === 'custom' && item.enabled)) {
    const parsed = readCustomFieldValue(field, formData)
    if (parsed.error) return parsed.error
    if (field.required && !parsed.hasValue) return `${field.label} is required.`
  }
  return null
}

export async function saveCustomFieldValues(
  supabase: any,
  entityType: EntityType,
  entityId: string,
  formData: FormData,
): Promise<string | null> {
  const { fields, error } = await fetchFieldDefinitions(supabase, entityType)
  if (error) return error.message

  const customFields = fields.filter((field) => field.source_type === 'custom' && field.enabled)

  for (const field of customFields) {
    const parsed = readCustomFieldValue(field, formData)
    if (parsed.error) return parsed.error
    if (field.required && !parsed.hasValue) return `${field.label} is required.`

    if (!parsed.hasValue && field.field_type !== 'boolean') {
      const { error: deleteError } = await supabase
        .from('record_custom_field_values')
        .delete()
        .eq('field_definition_id', field.id)
        .eq('entity_id', entityId)
      if (deleteError) return deleteError.message
      continue
    }

    const { error: upsertError } = await supabase
      .from('record_custom_field_values')
      .upsert(
        {
          field_definition_id: field.id,
          entity_id: entityId,
          value: parsed.value,
        },
        { onConflict: 'field_definition_id,entity_id' },
      )

    if (upsertError) return upsertError.message
  }
  return null
}
