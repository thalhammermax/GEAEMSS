'use server'

import { randomUUID } from 'node:crypto'
import { revalidatePath } from 'next/cache'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'

function value(formData: FormData, key: string) {
  const v = formData.get(key)
  return typeof v === 'string' ? v.trim() : ''
}
function checked(formData: FormData, key: string) { return formData.get(key) === 'on' }
function fail(path: string, message: string): never {
  redirect(`${path}${path.includes('?') ? '&' : '?'}error=${encodeURIComponent(message)}`)
}
function intValue(formData: FormData, key: string, fallback: number) {
  const raw = value(formData, key)
  if (!raw) return fallback
  const n = Number.parseInt(raw, 10)
  return Number.isInteger(n) ? n : fallback
}

async function requireEditableVersion(supabase: Awaited<ReturnType<typeof createClient>>, versionId: string, templateId: string) {
  const { data: version } = await supabase
    .from('inspection_form_versions')
    .select('id, template_id, status')
    .eq('id', versionId)
    .eq('template_id', templateId)
    .maybeSingle()
  if (!version || version.status !== 'draft') fail(`/inspections/forms/${templateId}`, 'Only an editable draft version can be changed.')
  return version
}


export async function createAgencyInspectionForm(formData: FormData) {
  const agencyId = value(formData, 'agency_id')
  const vehicleTypeId = value(formData, 'vehicle_type_id')
  const name = value(formData, 'name')
  const description = value(formData, 'description')
  const path = '/inspections/forms/new'
  if (!agencyId || !vehicleTypeId || !name) fail(path, 'Agency, vehicle type, and form name are required.')

  const supabase = await createClient()
  const { data, error } = await supabase.rpc('create_agency_inspection_form', {
    p_agency_id: agencyId,
    p_vehicle_type_id: vehicleTypeId,
    p_name: name,
    p_description: description || null,
  })
  if (error) fail(path, error.message)

  const templateId = String(data)
  revalidatePath('/inspections/forms')
  redirect(`/inspections/forms/${templateId}?notice=${encodeURIComponent('Agency inspection form created. Build the draft checklist, then publish it when ready.')}`)
}

export async function updateInspectionFormTemplate(formData: FormData) {
  const templateId = value(formData, 'template_id')
  const path = `/inspections/forms/${templateId}`
  if (!templateId) fail('/inspections/forms', 'Inspection form is missing.')

  const name = value(formData, 'name')
  if (!name) fail(path, 'Inspection form name is required.')

  const supabase = await createClient()
  const { error } = await supabase.from('inspection_form_templates').update({
    name,
    description: value(formData, 'description') || null,
    active: checked(formData, 'active'),
  }).eq('id', templateId)
  if (error) fail(path, error.message)

  revalidatePath('/inspections/forms')
  revalidatePath(path)
  redirect(`${path}?notice=${encodeURIComponent('Form settings saved.')}`)
}

export async function createInspectionFormDraft(formData: FormData) {
  const templateId = value(formData, 'template_id')
  const path = `/inspections/forms/${templateId}`
  if (!templateId) fail('/inspections/forms', 'Inspection form is missing.')
  const supabase = await createClient()
  const { error } = await supabase.rpc('create_inspection_form_draft', { p_template_id: templateId })
  if (error) fail(path, error.message)
  revalidatePath(path)
  redirect(`${path}?notice=${encodeURIComponent('Editable draft created from the published form.')}`)
}

export async function publishInspectionFormDraft(formData: FormData) {
  const templateId = value(formData, 'template_id')
  const versionId = value(formData, 'version_id')
  const path = `/inspections/forms/${templateId}`
  if (!templateId || !versionId) fail('/inspections/forms', 'Inspection form draft is missing.')
  const supabase = await createClient()
  const { error } = await supabase.rpc('publish_inspection_form_draft', { p_version_id: versionId })
  if (error) fail(path, error.message)
  revalidatePath('/inspections')
  revalidatePath('/inspections/new')
  revalidatePath('/inspections/forms')
  revalidatePath(path)
  redirect(`${path}?notice=${encodeURIComponent('New inspection form version published. Future inspections will use it.')}`)
}

export async function discardInspectionFormDraft(formData: FormData) {
  const templateId = value(formData, 'template_id')
  const versionId = value(formData, 'version_id')
  const path = `/inspections/forms/${templateId}`
  if (!templateId || !versionId) fail('/inspections/forms', 'Inspection form draft is missing.')
  const supabase = await createClient()
  const { error } = await supabase.from('inspection_form_versions').delete().eq('id', versionId).eq('template_id', templateId).eq('status', 'draft')
  if (error) fail(path, error.message)
  revalidatePath(path)
  redirect(`${path}?notice=${encodeURIComponent('Draft discarded. The published form was not changed.')}`)
}

export async function createInspectionSection(formData: FormData) {
  const templateId = value(formData, 'template_id')
  const versionId = value(formData, 'version_id')
  const path = `/inspections/forms/${templateId}`
  if (!templateId || !versionId) fail('/inspections/forms', 'Inspection form draft is missing.')
  const title = value(formData, 'title')
  if (!title) fail(path, 'Section title is required.')

  const supabase = await createClient()
  await requireEditableVersion(supabase, versionId, templateId)
  const { data: existing } = await supabase.from('inspection_form_sections').select('sort_order').eq('form_version_id', versionId).order('sort_order', { ascending: false }).limit(1)
  const sortOrder = intValue(formData, 'sort_order', ((existing?.[0]?.sort_order ?? 0) + 10))
  const { error } = await supabase.from('inspection_form_sections').insert({ form_version_id: versionId, title, sort_order: sortOrder })
  if (error) fail(path, error.message)
  revalidatePath(path)
  redirect(`${path}?notice=${encodeURIComponent('Section added.')}`)
}

export async function updateInspectionSection(formData: FormData) {
  const templateId = value(formData, 'template_id')
  const versionId = value(formData, 'version_id')
  const sectionId = value(formData, 'section_id')
  const path = `/inspections/forms/${templateId}`
  if (!templateId || !versionId || !sectionId) fail('/inspections/forms', 'Inspection section is missing.')
  const title = value(formData, 'title')
  if (!title) fail(path, 'Section title is required.')
  const supabase = await createClient()
  await requireEditableVersion(supabase, versionId, templateId)
  const { error } = await supabase.from('inspection_form_sections').update({ title, sort_order: intValue(formData, 'sort_order', 100) }).eq('id', sectionId).eq('form_version_id', versionId)
  if (error) fail(path, error.message)
  revalidatePath(path)
  redirect(`${path}?notice=${encodeURIComponent('Section updated.')}`)
}

export async function deleteInspectionSection(formData: FormData) {
  const templateId = value(formData, 'template_id')
  const versionId = value(formData, 'version_id')
  const sectionId = value(formData, 'section_id')
  const path = `/inspections/forms/${templateId}`
  if (!templateId || !versionId || !sectionId) fail('/inspections/forms', 'Inspection section is missing.')
  const supabase = await createClient()
  await requireEditableVersion(supabase, versionId, templateId)
  const { error } = await supabase.from('inspection_form_sections').delete().eq('id', sectionId).eq('form_version_id', versionId)
  if (error) fail(path, error.message)
  revalidatePath(path)
  redirect(`${path}?notice=${encodeURIComponent('Section and its items removed from the draft.')}`)
}

function itemPayload(formData: FormData) {
  const responseType = value(formData, 'response_type') || 'compliance'
  const allowedResponseTypes = new Set(['compliance','text','number','date','yes_no'])
  const severity = value(formData, 'failure_severity') || 'deficiency'
  const allowedSeverity = new Set(['advisory','deficiency','critical'])
  return {
    label: value(formData, 'label'),
    requirement_text: value(formData, 'requirement_text'),
    response_type: allowedResponseTypes.has(responseType) ? responseType : 'compliance',
    required: checked(formData, 'required'),
    allow_na: responseType === 'compliance' && checked(formData, 'allow_na'),
    failure_severity: allowedSeverity.has(severity) ? severity : 'deficiency',
    requires_comment_on_fail: responseType === 'compliance' && checked(formData, 'requires_comment_on_fail'),
    sort_order: intValue(formData, 'sort_order', 100),
  }
}

export async function createInspectionItem(formData: FormData) {
  const templateId = value(formData, 'template_id')
  const versionId = value(formData, 'version_id')
  const sectionId = value(formData, 'section_id')
  const path = `/inspections/forms/${templateId}`
  if (!templateId || !versionId || !sectionId) fail('/inspections/forms', 'Inspection section is missing.')
  const payload = itemPayload(formData)
  if (!payload.label || !payload.requirement_text) fail(path, 'Item name and requirement are required.')
  const supabase = await createClient()
  await requireEditableVersion(supabase, versionId, templateId)
  const { error } = await supabase.from('inspection_form_items').insert({
    section_id: sectionId,
    item_code: `CUSTOM_${randomUUID().replaceAll('-', '').slice(0, 20).toUpperCase()}`,
    ...payload,
  })
  if (error) fail(path, error.message)
  revalidatePath(path)
  redirect(`${path}?notice=${encodeURIComponent('Inspection item added.')}`)
}

export async function updateInspectionItem(formData: FormData) {
  const templateId = value(formData, 'template_id')
  const versionId = value(formData, 'version_id')
  const sectionId = value(formData, 'section_id')
  const itemId = value(formData, 'item_id')
  const path = `/inspections/forms/${templateId}`
  if (!templateId || !versionId || !sectionId || !itemId) fail('/inspections/forms', 'Inspection item is missing.')
  const payload = itemPayload(formData)
  if (!payload.label || !payload.requirement_text) fail(path, 'Item name and requirement are required.')
  const supabase = await createClient()
  await requireEditableVersion(supabase, versionId, templateId)
  const { error } = await supabase.from('inspection_form_items').update(payload).eq('id', itemId).eq('section_id', sectionId)
  if (error) fail(path, error.message)
  revalidatePath(path)
  redirect(`${path}?notice=${encodeURIComponent('Inspection item updated.')}`)
}

export async function deleteInspectionItem(formData: FormData) {
  const templateId = value(formData, 'template_id')
  const versionId = value(formData, 'version_id')
  const sectionId = value(formData, 'section_id')
  const itemId = value(formData, 'item_id')
  const path = `/inspections/forms/${templateId}`
  if (!templateId || !versionId || !sectionId || !itemId) fail('/inspections/forms', 'Inspection item is missing.')
  const supabase = await createClient()
  await requireEditableVersion(supabase, versionId, templateId)
  const { error } = await supabase.from('inspection_form_items').delete().eq('id', itemId).eq('section_id', sectionId)
  if (error) fail(path, error.message)
  revalidatePath(path)
  redirect(`${path}?notice=${encodeURIComponent('Inspection item removed from the draft.')}`)
}
