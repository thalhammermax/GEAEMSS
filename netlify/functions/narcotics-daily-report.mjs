import { createClient } from '@supabase/supabase-js'

function zonedParts(timeZone, date = new Date()) {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone,
    year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit',
    hour12: false, hourCycle: 'h23',
  }).formatToParts(date)
  const map = Object.fromEntries(parts.map((p) => [p.type, p.value]))
  return { date: `${map.year}-${map.month}-${map.day}`, hour: Number(map.hour) }
}
function esc(value) {
  return String(value ?? '').replace(/[&<>'"]/g, (ch) => ({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[ch]))
}

export default async () => {
  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL
  const secret = process.env.SUPABASE_SECRET_KEY
  const resendKey = process.env.RESEND_API_KEY
  const from = process.env.NARCOTICS_REPORT_FROM || 'GEAEMS Portal <no-reply@auth.geaemss.org>'
  if (!supabaseUrl || !secret || !resendKey) throw new Error('Narcotics report function is missing required environment variables.')
  const db = createClient(supabaseUrl, secret, { auth: { persistSession: false, autoRefreshToken: false } })
  const { data: moduleSetting, error: moduleError } = await db.from('system_module_settings').select('enabled').eq('module_key', 'narcotics').maybeSingle()
  // Narcotics is intentionally OFF by default during the initial staged rollout.
  // If migration 019 is not present yet, do not send controlled-substance reminders.
  if (moduleError || moduleSetting?.enabled !== true) return new Response('narcotics module disabled')
  const { data: settings, error: settingsError } = await db.from('narcotics_agency_settings').select('*, agencies(name, short_name)').eq('enabled', true).eq('send_incomplete_report', true)
  if (settingsError) throw settingsError

  for (const setting of settings ?? []) {
    const now = zonedParts(setting.timezone || 'America/Chicago')
    if (now.hour < Number(setting.report_hour ?? 8)) continue
    const { data: prior } = await db.from('narcotics_report_history').select('id').eq('agency_id', setting.agency_id).eq('report_date', now.date).eq('report_type', 'incomplete_daily_count').maybeSingle()
    if (prior) continue

    const { data: vehicles, error: vehicleError } = await db.from('vehicles').select('id, unit_number, fleet_number, vehicle_types(narcotics_template_id)').eq('agency_id', setting.agency_id).eq('active', true).eq('narcotics_count_required', true).order('unit_number')
    if (vehicleError) throw vehicleError
    const ids = (vehicles ?? []).map((v) => v.id)
    const { data: counts, error: countError } = ids.length ? await db.from('narcotics_counts').select('vehicle_id, status').in('vehicle_id', ids).eq('count_date', now.date) : { data: [], error: null }
    if (countError) throw countError
    const submitted = new Set((counts ?? []).filter((c) => c.status === 'submitted').map((c) => c.vehicle_id))
    const drafts = new Set((counts ?? []).filter((c) => c.status === 'draft').map((c) => c.vehicle_id))
    const missing = (vehicles ?? []).filter((v) => !submitted.has(v.id))

    if (missing.length === 0) {
      await db.from('narcotics_report_history').insert({ agency_id: setting.agency_id, report_date: now.date, status: 'skipped', missing_vehicle_ids: [], recipients: [] })
      continue
    }

    const { data: access } = await db.from('user_agency_access').select('user_id').eq('agency_id', setting.agency_id).eq('receive_narcotics_reports', true)
    const userIds = (access ?? []).map((r) => r.user_id)
    const [{ data: roles }, { data: profiles }] = userIds.length
      ? await Promise.all([
          db.from('user_roles').select('user_id').in('user_id', userIds).eq('role', 'agency_admin'),
          db.from('profiles').select('id').in('id', userIds).eq('active', true),
        ])
      : [{ data: [] }, { data: [] }]
    const allowedRoles = new Set((roles ?? []).map((r) => r.user_id))
    const activeUsers = new Set((profiles ?? []).map((p) => p.id))
    const emails = []
    for (const userId of userIds.filter((id) => allowedRoles.has(id) && activeUsers.has(id))) {
      const result = await db.auth.admin.getUserById(userId)
      const email = result.data.user?.email
      if (email) emails.push(email)
    }
    const uniqueEmails = [...new Set(emails)]
    if (uniqueEmails.length === 0) {
      console.warn(`No narcotics report recipients configured for agency ${setting.agency_id}`)
      continue
    }

    const agency = Array.isArray(setting.agencies) ? setting.agencies[0] : setting.agencies
    const rows = missing.map((v) => { const type = Array.isArray(v.vehicle_types) ? v.vehicle_types[0] : v.vehicle_types; const status = !type?.narcotics_template_id ? 'No form configured for vehicle type' : drafts.has(v.id) ? 'Draft not submitted' : 'Not started'; return `<tr><td style="padding:8px;border-bottom:1px solid #ddd">${esc(v.unit_number || v.fleet_number || 'Unnumbered')}</td><td style="padding:8px;border-bottom:1px solid #ddd">${esc(status)}</td></tr>` }).join('')
    const subject = `Incomplete narcotics counts - ${agency?.short_name || agency?.name || 'Agency'} - ${now.date}`
    const html = `<div style="font-family:Arial,sans-serif;color:#17212b"><h2>GEAEMS Narcotics Count Report</h2><p>The following apparatus do not have a submitted narcotics count for <strong>${esc(now.date)}</strong>.</p><table style="border-collapse:collapse;width:100%;max-width:640px"><thead><tr><th style="text-align:left;padding:8px;border-bottom:2px solid #999">Apparatus</th><th style="text-align:left;padding:8px;border-bottom:2px solid #999">Status</th></tr></thead><tbody>${rows}</tbody></table><p style="margin-top:20px"><a href="https://portal.geaemss.org/narcotics">Open GEAEMS Portal</a></p></div>`
    const response = await fetch('https://api.resend.com/emails', { method: 'POST', headers: { Authorization: `Bearer ${resendKey}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ from, to: uniqueEmails, subject, html }) })
    const body = await response.json().catch(() => ({}))
    if (!response.ok) { console.error('Resend failure', response.status, body); continue }
    await db.from('narcotics_report_history').insert({ agency_id: setting.agency_id, report_date: now.date, status: 'sent', missing_vehicle_ids: missing.map((v) => v.id), recipients: uniqueEmails, provider_message_id: body.id || null })
  }
  return new Response('ok')
}

export const config = { schedule: '@hourly' }
