'use server'

import { revalidatePath } from 'next/cache'
import { redirect } from 'next/navigation'
import { getCEContext, requireCEManager, requireCESessionManager } from '@/lib/ce-auth'
import { localDateTimeToUtc } from '@/lib/time-zone'

function text(formData: FormData, key: string) {
  const value = formData.get(key)
  return typeof value === 'string' ? value.trim() : ''
}
function bool(formData: FormData, key: string) { return formData.get(key) === 'on' || formData.get(key) === 'true' }
function numberOrNull(raw: string) {
  if (!raw) return null
  const value = Number(raw)
  if (!Number.isFinite(value)) throw new Error('A numeric value is invalid.')
  return value
}
function errorMessage(error: unknown, fallback: string) {
  return error instanceof Error && error.message ? error.message : fallback
}
function redirectError(path: string, error: unknown, fallback: string): never {
  redirect(`${path}${path.includes('?') ? '&' : '?'}error=${encodeURIComponent(errorMessage(error, fallback))}`)
}
function safeFilename(name: string) {
  return name.replace(/[^a-zA-Z0-9._-]+/g, '-').replace(/^-+|-+$/g, '').slice(-120) || 'certificate'
}

export async function createCECourse(formData: FormData) {
  let id = ''
  try {
    const { supabase, user } = await requireCEManager()
    const title = text(formData, 'title')
    const creditHours = Number(text(formData, 'credit_hours') || '0')
    if (!title) throw new Error('Course title is required.')
    if (!Number.isFinite(creditHours) || creditHours < 0) throw new Error('CE hours must be zero or greater.')

    const { data, error } = await supabase.from('ce_courses').insert({
      title,
      course_code: text(formData, 'course_code') || null,
      description: text(formData, 'description') || null,
      category: text(formData, 'category') || null,
      credit_hours: creditHours,
      active: true,
      created_by: user.id,
    }).select('id').single()
    if (error) throw error
    id = data.id
  } catch (error) {
    redirectError('/ce/courses/new', error, 'The CE class could not be created.')
  }
  revalidatePath('/ce')
  revalidatePath('/ce/courses')
  redirect(`/ce/courses/${id}?notice=${encodeURIComponent('CE class created. Add one or more scheduled sessions below.')}`)
}

export async function addCESession(formData: FormData) {
  const courseId = text(formData, 'course_id')
  try {
    if (!courseId) throw new Error('Course is required.')
    const { supabase, user } = await requireCEManager()
    const timezone = text(formData, 'timezone') || 'America/Chicago'
    const startAt = localDateTimeToUtc(text(formData, 'start_at'), timezone)
    const endAt = localDateTimeToUtc(text(formData, 'end_at'), timezone)
    if (new Date(endAt) <= new Date(startAt)) throw new Error('The session end time must be after the start time.')

    const capacity = numberOrNull(text(formData, 'capacity'))
    const hours = numberOrNull(text(formData, 'credit_hours_override'))
    if (capacity !== null && capacity <= 0) throw new Error('Capacity must be greater than zero.')
    if (hours !== null && hours < 0) throw new Error('CE hours must be zero or greater.')

    const { error } = await supabase.from('ce_sessions').insert({
      course_id: courseId,
      start_at: startAt,
      end_at: endAt,
      timezone,
      location_name: text(formData, 'location_name') || null,
      location_address: text(formData, 'location_address') || null,
      capacity,
      credit_hours_override: hours,
      self_checkin_enabled: bool(formData, 'self_checkin_enabled'),
      check_in_open_minutes: Number(text(formData, 'check_in_open_minutes') || '60'),
      verification_close_hours: Number(text(formData, 'verification_close_hours') || '24'),
      notes: text(formData, 'notes') || null,
      created_by: user.id,
    })
    if (error) throw error
  } catch (error) {
    redirectError(`/ce/courses/${courseId}`, error, 'The CE session could not be scheduled.')
  }
  revalidatePath('/ce')
  revalidatePath(`/ce/courses/${courseId}`)
  redirect(`/ce/courses/${courseId}?notice=${encodeURIComponent('Session added to the class schedule.')}`)
}

export async function updateCESession(formData: FormData) {
  const sessionId = text(formData, 'session_id')
  try {
    if (!sessionId) throw new Error('Session is required.')
    const { supabase } = await requireCEManager()
    const timezone = text(formData, 'timezone') || 'America/Chicago'
    const startAt = localDateTimeToUtc(text(formData, 'start_at'), timezone)
    const endAt = localDateTimeToUtc(text(formData, 'end_at'), timezone)
    if (new Date(endAt) <= new Date(startAt)) throw new Error('The session end time must be after the start time.')
    const capacity = numberOrNull(text(formData, 'capacity'))
    const hours = numberOrNull(text(formData, 'credit_hours_override'))
    const status = text(formData, 'status') || 'scheduled'
    if (!['scheduled','cancelled','completed'].includes(status)) throw new Error('Session status is invalid.')

    const { error } = await supabase.from('ce_sessions').update({
      start_at: startAt,
      end_at: endAt,
      timezone,
      location_name: text(formData, 'location_name') || null,
      location_address: text(formData, 'location_address') || null,
      capacity,
      credit_hours_override: hours,
      self_checkin_enabled: bool(formData, 'self_checkin_enabled'),
      check_in_open_minutes: Number(text(formData, 'check_in_open_minutes') || '60'),
      verification_close_hours: Number(text(formData, 'verification_close_hours') || '24'),
      status,
      notes: text(formData, 'notes') || null,
      updated_at: new Date().toISOString(),
    }).eq('id', sessionId)
    if (error) throw error
  } catch (error) {
    redirectError(`/ce/sessions/${sessionId}`, error, 'The session could not be updated.')
  }
  revalidatePath('/ce')
  revalidatePath(`/ce/sessions/${sessionId}`)
  redirect(`/ce/sessions/${sessionId}?notice=${encodeURIComponent('Session details updated.')}`)
}

export async function assignCEInstructor(formData: FormData) {
  const sessionId = text(formData, 'session_id')
  const instructorId = text(formData, 'user_id')
  try {
    const { supabase, user } = await requireCEManager()
    if (!sessionId || !instructorId) throw new Error('Session and instructor are required.')
    const { data: role, error: roleError } = await supabase.from('user_roles').select('role').eq('user_id', instructorId).eq('role', 'ce_instructor').maybeSingle()
    if (roleError) throw roleError
    if (!role) throw new Error('That user does not have the CE Instructor role.')
    const { error } = await supabase.from('ce_session_instructors').upsert({ session_id: sessionId, user_id: instructorId, assigned_by: user.id }, { onConflict: 'session_id,user_id' })
    if (error) throw error
  } catch (error) {
    redirectError(`/ce/sessions/${sessionId}`, error, 'The instructor could not be assigned.')
  }
  revalidatePath(`/ce/sessions/${sessionId}`)
  redirect(`/ce/sessions/${sessionId}?notice=${encodeURIComponent('Instructor assigned.')}`)
}

export async function removeCEInstructor(formData: FormData) {
  const sessionId = text(formData, 'session_id')
  const instructorId = text(formData, 'user_id')
  try {
    const { supabase } = await requireCEManager()
    if (!sessionId || !instructorId) throw new Error('Session and instructor are required.')
    const { error } = await supabase.from('ce_session_instructors').delete().eq('session_id', sessionId).eq('user_id', instructorId)
    if (error) throw error
  } catch (error) {
    redirectError(`/ce/sessions/${sessionId}`, error, 'The instructor assignment could not be removed.')
  }
  revalidatePath(`/ce/sessions/${sessionId}`)
  redirect(`/ce/sessions/${sessionId}?notice=${encodeURIComponent('Instructor removed.')}`)
}

export async function selfCheckInCE(formData: FormData) {
  const sessionId = text(formData, 'session_id')
  try {
    const { supabase, providerId } = await getCEContext()
    if (!providerId) throw new Error('A linked provider record is required to check in.')
    const { error } = await supabase.rpc('ce_self_check_in', { p_session_id: sessionId })
    if (error) throw error
  } catch (error) {
    redirectError('/ce', error, 'Check-in could not be completed.')
  }
  revalidatePath('/ce')
  redirect(`/ce?notice=${encodeURIComponent('You are checked in. Enter the completion code when your instructor releases it at the end of class.')}`)
}

export async function verifyCEAttendance(formData: FormData) {
  const sessionId = text(formData, 'session_id')
  try {
    const { supabase, providerId } = await getCEContext()
    if (!providerId) throw new Error('A linked provider record is required.')
    const code = text(formData, 'verification_code')
    if (!code) throw new Error('Enter the completion code provided by the instructor.')
    const { error } = await supabase.rpc('ce_verify_attendance', { p_session_id: sessionId, p_code: code })
    if (error) throw error
  } catch (error) {
    redirectError('/ce', error, 'Attendance could not be verified.')
  }
  revalidatePath('/ce')
  revalidatePath('/ce/transcript')
  redirect(`/ce?notice=${encodeURIComponent('Attendance verified. CE credit has been added to your transcript.')}`)
}

export async function generateCEVerificationCode(formData: FormData) {
  const sessionId = text(formData, 'session_id')
  try {
    const { supabase } = await requireCESessionManager(sessionId)
    const { error } = await supabase.rpc('ce_generate_verification_code', { p_session_id: sessionId })
    if (error) throw error
  } catch (error) {
    redirectError(`/ce/sessions/${sessionId}`, error, 'The completion code could not be generated.')
  }
  revalidatePath('/ce')
  revalidatePath(`/ce/sessions/${sessionId}`)
  redirect(`/ce/sessions/${sessionId}?notice=${encodeURIComponent('Completion code released to the session.')}`)
}

export async function manualCEAttendance(formData: FormData) {
  const sessionId = text(formData, 'session_id')
  try {
    const { supabase } = await requireCESessionManager(sessionId)
    const providerId = text(formData, 'provider_id')
    if (!providerId) throw new Error('Select a provider.')
    const completed = bool(formData, 'completed')
    const { error } = await supabase.rpc('ce_manual_mark_attendance', {
      p_session_id: sessionId,
      p_provider_id: providerId,
      p_completed: completed,
      p_notes: text(formData, 'notes') || null,
    })
    if (error) throw error
  } catch (error) {
    redirectError(`/ce/sessions/${sessionId}`, error, 'Attendance could not be entered.')
  }
  revalidatePath('/ce')
  revalidatePath(`/ce/sessions/${sessionId}`)
  revalidatePath('/ce/transcript')
  redirect(`/ce/sessions/${sessionId}?notice=${encodeURIComponent('Roster entry saved.')}`)
}

export async function submitExternalCE(formData: FormData) {
  let submissionId = ''
  try {
    const { supabase, user, providerId } = await getCEContext()
    if (!providerId) throw new Error('A linked provider record is required to submit CE.')
    const title = text(formData, 'title')
    const completionDate = text(formData, 'completion_date')
    const creditHours = Number(text(formData, 'credit_hours') || '0')
    const file = formData.get('certificate')
    if (!title) throw new Error('Training title is required.')
    if (!completionDate) throw new Error('Completion date is required.')
    if (!Number.isFinite(creditHours) || creditHours < 0) throw new Error('CE hours must be zero or greater.')
    if (!(file instanceof File) || file.size <= 0) throw new Error('A completion certificate is required for external or online CE.')
    if (file.size > 10 * 1024 * 1024) throw new Error('The certificate must be 10 MB or smaller.')
    const allowed = new Set(['application/pdf','image/jpeg','image/png','image/webp'])
    if (!allowed.has(file.type)) throw new Error('Certificate must be a PDF, JPG, PNG, or WebP file.')

    const { data: submission, error: insertError } = await supabase.from('ce_external_submissions').insert({
      provider_id: providerId,
      title,
      sponsor: text(formData, 'sponsor') || null,
      category: text(formData, 'category') || null,
      completion_date: completionDate,
      credit_hours: creditHours,
      notes: text(formData, 'notes') || null,
      status: 'pending',
      submitted_by: user.id,
    }).select('id').single()
    if (insertError) throw insertError
    submissionId = submission.id

    const filename = safeFilename(file.name)
    const path = `${providerId}/${submissionId}/${Date.now()}-${filename}`
    const bytes = await file.arrayBuffer()
    const { error: uploadError } = await supabase.storage.from('ce-certificates').upload(path, bytes, { contentType: file.type, upsert: false })
    if (uploadError) {
      await supabase.from('ce_external_submissions').delete().eq('id', submissionId)
      throw uploadError
    }
    const { error: updateError } = await supabase.from('ce_external_submissions').update({ certificate_path: path, certificate_filename: file.name, updated_at: new Date().toISOString() }).eq('id', submissionId)
    if (updateError) throw updateError
  } catch (error) {
    redirectError('/ce/external/new', error, 'The external CE submission could not be saved.')
  }
  revalidatePath('/ce')
  revalidatePath('/ce/external/review')
  redirect(`/ce?notice=${encodeURIComponent('External CE submitted for coordinator review.')}`)
}

export async function reviewExternalCE(formData: FormData) {
  const submissionId = text(formData, 'submission_id')
  try {
    const { supabase } = await requireCEManager()
    const decision = text(formData, 'decision')
    if (!submissionId) throw new Error('Submission is required.')
    if (!['approved','rejected'].includes(decision)) throw new Error('Choose Approve or Reject.')
    const { error } = await supabase.rpc('review_external_ce', {
      p_submission_id: submissionId,
      p_decision: decision,
      p_notes: text(formData, 'review_notes') || null,
    })
    if (error) throw error
  } catch (error) {
    redirectError('/ce/external/review', error, 'The CE submission could not be reviewed.')
  }
  revalidatePath('/ce')
  revalidatePath('/ce/external/review')
  revalidatePath('/ce/transcript')
  redirect(`/ce/external/review?notice=${encodeURIComponent('External CE review saved.')}`)
}
