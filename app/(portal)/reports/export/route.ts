import { NextRequest } from 'next/server'
import { requireReportAdmin } from '@/lib/report-auth'
import { builtInFor, type ReportDefinition } from '@/lib/report-catalog'
import { csvForReport, runReport } from '@/lib/report-data'

function fromSaved(row:any):ReportDefinition { return { id:row.id,name:row.name,description:row.description||'',dataSource:row.data_source,columns:Array.isArray(row.selected_columns)?row.selected_columns:[],filters:Array.isArray(row.filters)?row.filters:[],sortField:row.sort_field||undefined,sortDirection:row.sort_direction||'asc',groupField:row.group_field||undefined } }
function filename(text:string) { return text.replace(/[^a-z0-9]+/gi,'-').replace(/^-|-$/g,'').toLowerCase().slice(0,80) || 'report' }

export async function GET(request:NextRequest) {
  const { supabase } = await requireReportAdmin()
  const id = request.nextUrl.searchParams.get('id'); const presetKey = request.nextUrl.searchParams.get('preset')
  let definition:ReportDefinition | null = null; let name='GEAEMS Report'
  if (id) { const { data } = await supabase.from('saved_reports').select('*').eq('id',id).maybeSingle(); if (data) { definition=fromSaved(data); name=data.name } }
  else if (presetKey) { const preset=builtInFor(presetKey); if (preset) { definition=preset.definition; name=preset.name } }
  if (!definition) return new Response('Report not found.',{status:404})
  const result = await runReport(supabase,definition)
  const csv = '\uFEFF' + csvForReport(result.rows,result.fields,result.columns)
  return new Response(csv,{headers:{'Content-Type':'text/csv; charset=utf-8','Content-Disposition':`attachment; filename="${filename(name)}.csv"`,'Cache-Control':'no-store'}})
}
