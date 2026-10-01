import { createClient } from '@supabase/supabase-js'
import { csvForReport, runReport, type ReportScope } from '../../lib/report-data'
import { sourceAvailableForModules, sourceRequiredModules, type ReportDefinition } from '../../lib/report-catalog'
import { enabledModuleKeys, getModuleStates, moduleLabel } from '../../lib/modules'

function zonedParts(timeZone:string, date = new Date()) {
  const parts = new Intl.DateTimeFormat('en-CA', { timeZone, year:'numeric', month:'2-digit', day:'2-digit', hour:'2-digit', hour12:false, hourCycle:'h23' }).formatToParts(date)
  const map = Object.fromEntries(parts.map((p) => [p.type,p.value])) as Record<string,string>
  const year=Number(map.year), month=Number(map.month), day=Number(map.day)
  return { year, month, day, date:`${map.year}-${map.month}-${map.day}`, hour:Number(map.hour), weekday:new Date(Date.UTC(year,month-1,day)).getUTCDay(), daysInMonth:new Date(Date.UTC(year,month,0)).getUTCDate() }
}
function due(report:any, now:ReturnType<typeof zonedParts>) {
  if (!report.schedule_enabled || !report.schedule_frequency) return false
  if (now.hour < Number(report.schedule_hour ?? 8)) return false
  if (report.schedule_frequency === 'weekly' && now.weekday !== Number(report.schedule_weekday)) return false
  if (report.schedule_frequency === 'monthly') {
    const desired = Number(report.schedule_day_of_month ?? 1)
    if (now.day !== Math.min(desired, now.daysInMonth)) return false
  }
  return true
}
function runKey(report:any, now:ReturnType<typeof zonedParts>) {
  if (report.schedule_frequency === 'monthly') return `monthly:${now.year}-${String(now.month).padStart(2,'0')}`
  if (report.schedule_frequency === 'weekly') return `weekly:${now.date}`
  return `daily:${now.date}`
}
function esc(value:any) { return String(value ?? '').replace(/[&<>'"]/g,(ch) => ({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[ch] || ch)) }
function filename(text:string) { return text.replace(/[^a-z0-9]+/gi,'-').replace(/^-|-$/g,'').toLowerCase().slice(0,80) || 'geaems-report' }
function fromSaved(row:any):ReportDefinition { return { id:row.id,name:row.name,description:row.description||'',dataSource:row.data_source,columns:Array.isArray(row.selected_columns)?row.selected_columns:[],filters:Array.isArray(row.filters)?row.filters:[],sortField:row.sort_field||undefined,sortDirection:row.sort_direction||'asc',groupField:row.group_field||undefined } }

async function ownerScope(db:any, userId:string):Promise<ReportScope | null> {
  const [{ data:profile }, { data:roles }] = await Promise.all([
    db.from('profiles').select('active').eq('id',userId).maybeSingle(),
    db.from('user_roles').select('role').eq('user_id',userId),
  ])
  if (!profile || profile.active === false) return null
  const names = new Set((roles ?? []).map((r:any) => r.role))
  if (names.has('system_admin')) return { isSystemAdmin:true, agencyIds:[] }
  if (!names.has('agency_admin')) return null
  const { data:access } = await db.from('user_agency_access').select('agency_id').eq('user_id',userId)
  return { isSystemAdmin:false, agencyIds:[...new Set((access ?? []).map((r:any) => r.agency_id))] as string[] }
}

function htmlTable(rows:Record<string,any>[], fields:any[], columns:string[]) {
  const labels = new Map(fields.map((f:any) => [f.key,f.label]))
  const shown = rows.slice(0,200)
  const head = columns.map((c) => `<th style="text-align:left;padding:8px;border-bottom:2px solid #98a2ad;background:#f5f7f9">${esc(labels.get(c) || c)}</th>`).join('')
  const body = shown.map((row) => `<tr>${columns.map((c) => `<td style="padding:8px;border-bottom:1px solid #e3e7eb;vertical-align:top">${esc(typeof row[c] === 'boolean' ? (row[c]?'Yes':'No') : row[c] ?? '')}</td>`).join('')}</tr>`).join('')
  const note = rows.length > shown.length ? `<p style="color:#667085;font-size:12px">Email table limited to the first ${shown.length} of ${rows.length} rows. The CSV attachment contains the complete report.</p>` : ''
  return `${note}<div style="overflow:auto"><table style="border-collapse:collapse;width:100%;font-size:12px"><thead><tr>${head}</tr></thead><tbody>${body}</tbody></table></div>`
}

export default async () => {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL
  const secret = process.env.SUPABASE_SECRET_KEY
  const resend = process.env.RESEND_API_KEY
  const from = process.env.REPORTS_FROM || 'GEAEMS Portal <no-reply@auth.geaemss.org>'
  const portalUrl = process.env.NEXT_PUBLIC_SITE_URL || 'https://portal.geaemss.org'
  if (!url || !secret || !resend) throw new Error('Scheduled reports are missing required environment variables.')
  const db = createClient(url,secret,{auth:{persistSession:false,autoRefreshToken:false}})
  const moduleStates = await getModuleStates(db)
  if (!moduleStates.reports) return new Response('reports module disabled')
  const enabledModules = new Set(enabledModuleKeys(moduleStates))
  const { data:reports, error } = await db.from('saved_reports').select('*').eq('schedule_enabled',true)
  if (error) throw error

  for (const report of reports ?? []) {
    const timezone = report.schedule_timezone || 'America/Chicago'
    const now = zonedParts(timezone)
    if (!due(report,now)) continue
    const key = runKey(report,now)
    const { data:prior } = await db.from('report_schedule_runs').select('id').eq('saved_report_id',report.id).eq('run_key',key).maybeSingle()
    if (prior) continue

    const recipients = [...new Set((report.schedule_recipients ?? []).map((v:string) => String(v).trim().toLowerCase()).filter(Boolean))]
    if (!sourceAvailableForModules(report.data_source, enabledModules)) {
      const missing = sourceRequiredModules(report.data_source).filter((module) => !enabledModules.has(module)).map(moduleLabel).join(', ')
      const message = `Scheduled report skipped because these modules are disabled: ${missing || 'required module'}.`
      await db.from('report_schedule_runs').insert({ saved_report_id:report.id, run_key:key, scheduled_local_date:now.date, status:'skipped', recipients, recipient_count:recipients.length, row_count:0, error_message:message })
      await db.from('saved_reports').update({ last_run_at:new Date().toISOString(), last_run_status:'skipped', last_run_message:message }).eq('id',report.id)
      continue
    }
    const scope = await ownerScope(db,report.owner_user_id)
    if (!scope) {
      const message = 'Report owner no longer has an active System Administrator or Agency Administrator role.'
      await db.from('report_schedule_runs').insert({ saved_report_id:report.id, run_key:key, scheduled_local_date:now.date, status:'skipped', recipients, recipient_count:recipients.length, row_count:0, error_message:message })
      await db.from('saved_reports').update({ last_run_at:new Date().toISOString(), last_run_status:'skipped', last_run_message:message }).eq('id',report.id)
      continue
    }
    if (!scope.isSystemAdmin && scope.agencyIds.length === 0) {
      const message = 'Report owner has no current agency administration assignments.'
      await db.from('report_schedule_runs').insert({ saved_report_id:report.id, run_key:key, scheduled_local_date:now.date, status:'skipped', recipients, recipient_count:recipients.length, row_count:0, error_message:message })
      await db.from('saved_reports').update({ last_run_at:new Date().toISOString(), last_run_status:'skipped', last_run_message:message }).eq('id',report.id)
      continue
    }
    try {
      const definition = fromSaved(report)
      const output = await runReport(db,definition,scope)
      const csv = '\uFEFF' + csvForReport(output.rows,output.fields,output.columns)
      const delivery = report.schedule_delivery_mode || 'inline_csv'
      const includeTable = delivery === 'inline' || delivery === 'inline_csv'
      const includeCsv = delivery === 'csv' || delivery === 'inline_csv'
      const html = `<div style="font-family:Arial,sans-serif;color:#17212b;max-width:1000px"><div style="border-bottom:4px solid #c41f2b;padding-bottom:12px;margin-bottom:18px"><h2 style="margin:0;color:#142c46">${esc(report.name)}</h2><p style="margin:6px 0 0;color:#667085">GEAEMS Portal scheduled report · ${esc(now.date)} · ${output.rows.length} row${output.rows.length===1?'':'s'}</p></div>${report.description?`<p>${esc(report.description)}</p>`:''}${includeTable?htmlTable(output.rows,output.fields,output.columns):'<p>The complete report is attached as a CSV file.</p>'}<p style="margin-top:22px"><a href="${esc(portalUrl)}/reports/${esc(report.id)}">Open this report in GEAEMS Portal</a></p><p style="font-size:11px;color:#98a2ad">This report was generated using the report owner's current portal permissions at delivery time.</p></div>`
      const payload:any = { from, to:recipients, subject:`GEAEMS Report: ${report.name} - ${now.date}`, html }
      if (includeCsv) payload.attachments = [{ filename:`${filename(report.name)}-${now.date}.csv`, content:Buffer.from(csv,'utf8').toString('base64') }]
      const response = await fetch('https://api.resend.com/emails',{method:'POST',headers:{Authorization:`Bearer ${resend}`,'Content-Type':'application/json'},body:JSON.stringify(payload)})
      const body:any = await response.json().catch(() => ({}))
      if (!response.ok) throw new Error(body?.message || `Email provider returned HTTP ${response.status}.`)
      await db.from('report_schedule_runs').insert({ saved_report_id:report.id, run_key:key, scheduled_local_date:now.date, status:'sent', recipients, recipient_count:recipients.length, row_count:output.rows.length, provider_message_id:body.id || null })
      await db.from('saved_reports').update({ last_run_at:new Date().toISOString(), last_run_status:'sent', last_run_message:`Sent ${output.rows.length} rows to ${recipients.length} recipient(s).` }).eq('id',report.id)
    } catch (e:any) {
      const message = String(e?.message || 'Scheduled report failed.').slice(0,2000)
      console.error('Scheduled report failed',report.id,message)
      await db.from('report_schedule_runs').insert({ saved_report_id:report.id, run_key:key, scheduled_local_date:now.date, status:'failed', recipients, recipient_count:recipients.length, row_count:0, error_message:message })
      await db.from('saved_reports').update({ last_run_at:new Date().toISOString(), last_run_status:'failed', last_run_message:message }).eq('id',report.id)
    }
  }
  return new Response('ok')
}

export const config = { schedule:'@hourly' }
