'use server'

import { revalidatePath } from 'next/cache'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { getCredentialAdminContext } from '@/lib/credential-access'

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

function definitionPayload(formData: FormData) {
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

function ensureValidDefinition(path: string, data: ReturnType<typeof definitionPayload>) {
  if (!data.code || !data.name) fail(path, 'Credential name and code are required.')
  if (data.renewal_months !== null && (!Number.isInteger(data.renewal_months) || data.renewal_months <= 0)) {
    fail(path, 'Renewal months must be a positive whole number.')
  }
}

function canManageAgency(agencies: any[], agencyId: string) {
  return agencies.some((a: any) => a.id === agencyId)
}

export async function createCredentialType(formData: FormData) {
  const path = '/credentials/new'
  const data = definitionPayload(formData)
  ensureValidDefinition(path, data)

  const supabase = await createClient()
  const context = await getCredentialAdminContext(supabase)
  if (!context.isSystemAdmin && !context.isAgencyAdmin) fail('/dashboard', 'Credential administration access is required.')

  let scopeType = value(formData, 'scope_type') || 'agency'
  let agencyId = value(formData, 'agency_id') || null

  if (!context.isSystemAdmin) scopeType = 'agency'
  if (scopeType !== 'system' && scopeType !== 'agency') fail(path, 'Invalid credential ownership scope.')

  if (scopeType === 'system') {
    if (!context.isSystemAdmin) fail(path, 'Only a System Administrator can create System credentials.')
    agencyId = null
  } else {
    if (!agencyId) fail(path, 'Choose the agency that owns this credential.')
    if (!canManageAgency(context.manageableAgencies, agencyId)) fail(path, 'You do not have credential administration access for that agency.')
  }

  const { data: created, error } = await supabase.from('credential_types').insert({
    ...data,
    scope_type: scopeType,
    agency_id: agencyId,
    created_by: context.user.id,
  }).select('id').single()

  if (error || !created) fail(path, error?.message ?? 'Credential type could not be created.')
  revalidatePath('/credentials')
  redirect(`/credentials/${created.id}/edit?saved=1`)
}

export async function updateCredentialType(formData: FormData) {
  const id = value(formData, 'id')
  const path = `/credentials/${id}/edit`
  if (!id) fail('/credentials', 'Credential ID is missing.')
  const data = definitionPayload(formData)
  ensureValidDefinition(path, data)

  const supabase = await createClient()
  const context = await getCredentialAdminContext(supabase)
  const { data: credential } = await supabase.from('credential_types').select('id, scope_type, agency_id').eq('id', id).maybeSingle()
  if (!credential) fail('/credentials', 'Credential not found or you do not have access to it.')

  const allowed = context.isSystemAdmin || (
    credential.scope_type === 'agency'
    && credential.agency_id
    && canManageAgency(context.manageableAgencies, credential.agency_id)
  )
  if (!allowed) fail(path, 'You may view this credential, but only its owner can edit the definition.')

  const { error } = await supabase.from('credential_types').update(data).eq('id', id)
  if (error) fail(path, error.message)
  revalidatePath('/credentials')
  revalidatePath(path)
  redirect(`${path}?saved=1`)
}

export async function setCredentialTypeActive(formData: FormData) {
  const id = value(formData, 'id')
  const active = value(formData, 'active') === 'true'
  if (!id) fail('/credentials', 'Credential ID is missing.')
  const supabase = await createClient()
  const context = await getCredentialAdminContext(supabase)
  const { data: credential } = await supabase.from('credential_types').select('id, scope_type, agency_id').eq('id', id).maybeSingle()
  if (!credential) fail('/credentials', 'Credential not found or you do not have access to it.')
  const allowed = context.isSystemAdmin || (
    credential.scope_type === 'agency'
    && credential.agency_id
    && canManageAgency(context.manageableAgencies, credential.agency_id)
  )
  if (!allowed) fail('/credentials', 'You cannot change this credential.')
  const { error } = await supabase.from('credential_types').update({ active }).eq('id', id)
  if (error) fail('/credentials', error.message)
  revalidatePath('/credentials')
  redirect('/credentials')
}

export async function deleteCredentialType(formData: FormData) {
  const id = value(formData, 'id')
  if (!id) fail('/credentials', 'Credential ID is missing.')
  const supabase = await createClient()
  const context = await getCredentialAdminContext(supabase)
  const { data: credential } = await supabase.from('credential_types').select('id, scope_type, agency_id').eq('id', id).maybeSingle()
  if (!credential) fail('/credentials', 'Credential not found or you do not have access to it.')
  const allowed = context.isSystemAdmin || (
    credential.scope_type === 'agency'
    && credential.agency_id
    && canManageAgency(context.manageableAgencies, credential.agency_id)
  )
  if (!allowed) fail('/credentials', 'You cannot delete this credential.')

  // Agency administrators may retire their local definitions, but permanent
  // deletion is reserved for System Administration so hidden historical rows
  // from former affiliations cannot be accidentally destroyed.
  if (!context.isSystemAdmin) {
    const { error } = await supabase.from('credential_types').update({ active: false }).eq('id', id)
    if (error) fail('/credentials', error.message)
    revalidatePath('/credentials')
    redirect('/credentials?notice=' + encodeURIComponent('Agency credential deactivated. Historical data was preserved.'))
  }

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

export async function createCredentialRequirement(formData: FormData) {
  const credentialTypeId = value(formData, 'credential_type_id')
  const path = `/credentials/${credentialTypeId}/edit`
  if (!credentialTypeId) fail('/credentials', 'Credential ID is missing.')

  const supabase = await createClient()
  const context = await getCredentialAdminContext(supabase)
  const { data: credential } = await supabase.from('credential_types').select('id, scope_type, agency_id').eq('id', credentialTypeId).maybeSingle()
  if (!credential) fail('/credentials', 'Credential not found or you do not have access to it.')

  let scopeType = value(formData, 'requirement_scope') || 'agency'
  let agencyId = value(formData, 'requirement_agency_id') || null
  const providerLevelId = value(formData, 'provider_level_id') || null
  const startDate = value(formData, 'effective_start_date') || null
  const endDate = value(formData, 'effective_end_date') || null
  const notes = value(formData, 'requirement_notes') || null

  if (!context.isSystemAdmin) scopeType = 'agency'

  if (scopeType === 'system') {
    if (!context.isSystemAdmin) fail(path, 'Only a System Administrator can create a System-wide requirement.')
    if (credential.scope_type !== 'system') fail(path, 'Agency-owned credentials cannot be required system-wide.')
    agencyId = null
  } else if (scopeType === 'agency') {
    if (credential.scope_type === 'agency') agencyId = credential.agency_id
    if (!agencyId) fail(path, 'Choose an agency for this requirement.')
    if (!canManageAgency(context.manageableAgencies, agencyId) && !context.isSystemAdmin) fail(path, 'You cannot manage credential requirements for that agency.')
    if (credential.scope_type === 'agency' && credential.agency_id !== agencyId) fail(path, 'An agency credential can only be required by its owning agency.')
  } else {
    fail(path, 'Invalid requirement scope.')
  }

  const { error } = await supabase.from('credential_requirements').insert({
    credential_type_id: credentialTypeId,
    scope_type: scopeType,
    agency_id: agencyId,
    provider_level_id: providerLevelId,
    required: true,
    effective_start_date: startDate,
    effective_end_date: endDate,
    notes,
  })
  if (error) fail(path, error.message)
  revalidatePath(path)
  revalidatePath('/credentials')
  redirect(`${path}?notice=${encodeURIComponent('Credential requirement added.')}`)
}

export async function deleteCredentialRequirement(formData: FormData) {
  const requirementId = value(formData, 'requirement_id')
  const credentialTypeId = value(formData, 'credential_type_id')
  const path = `/credentials/${credentialTypeId}/edit`
  if (!requirementId || !credentialTypeId) fail('/credentials', 'Requirement information is missing.')

  const supabase = await createClient()
  const context = await getCredentialAdminContext(supabase)
  const { data: requirement } = await supabase.from('credential_requirements').select('id, scope_type, agency_id').eq('id', requirementId).eq('credential_type_id', credentialTypeId).maybeSingle()
  if (!requirement) fail(path, 'Requirement not found or you do not have access to it.')

  const allowed = context.isSystemAdmin || (
    requirement.scope_type === 'agency'
    && requirement.agency_id
    && canManageAgency(context.manageableAgencies, requirement.agency_id)
  )
  if (!allowed) fail(path, 'You cannot remove this requirement.')

  const { error } = await supabase.from('credential_requirements').delete().eq('id', requirementId)
  if (error) fail(path, error.message)
  revalidatePath(path)
  revalidatePath('/credentials')
  redirect(`${path}?notice=${encodeURIComponent('Credential requirement removed.')}`)
}
