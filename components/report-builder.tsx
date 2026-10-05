'use client'

import { Fragment, useMemo, useState, useTransition } from 'react'
import { useRouter } from 'next/navigation'
import type { ReportDefinition, ReportField, ReportFilter, ReportSource } from '@/lib/report-catalog'
import { moduleLabel } from '@/lib/modules'
import { formatDate, formatDateTime, formatHour24 } from '@/lib/format'
import { previewReportAction, saveReportAction } from '@/app/(portal)/reports/actions'

type Props = {
  sources: ReportSource[]
  fieldsBySource: Record<string, ReportField[]>
  initial: ReportDefinition
  presetName?: string
}

type Preview = { rows: Record<string, any>[]; fields: ReportField[]; columns: string[]; totalRows: number } | null

const operators: Record<string, { value: string; label: string }[]> = {
  text: [
    { value: 'equals', label: 'equals' }, { value: 'not_equals', label: 'does not equal' },
    { value: 'contains', label: 'contains' }, { value: 'not_contains', label: 'does not contain' },
    { value: 'starts_with', label: 'starts with' }, { value: 'one_of', label: 'is one of (comma-separated)' },
    { value: 'is_empty', label: 'is empty' }, { value: 'not_empty', label: 'is not empty' },
  ],
  number: [
    { value: 'equals', label: 'equals' }, { value: 'not_equals', label: 'does not equal' },
    { value: 'gte', label: 'is greater than or equal to' }, { value: 'lte', label: 'is less than or equal to' },
    { value: 'is_empty', label: 'is empty' }, { value: 'not_empty', label: 'is not empty' },
  ],
  date: [
    { value: 'equals', label: 'is on' }, { value: 'after', label: 'is after' }, { value: 'before', label: 'is before' },
    { value: 'is_empty', label: 'is empty' }, { value: 'not_empty', label: 'is not empty' },
  ],
  boolean: [
    { value: 'equals', label: 'equals' }, { value: 'not_equals', label: 'does not equal' },
  ],
}

function formatValue(value: any, field?: ReportField) {
  if (value == null || value === '') return '—'
  if (typeof value === 'boolean') return value ? 'Yes' : 'No'
  if (field?.type === 'date') {
    return String(value).length === 10 ? formatDate(String(value)) : formatDateTime(String(value))
  }
  return String(value)
}

function hourLabel(hour: number) {
  return formatHour24(hour)
}

export function ReportBuilder({ sources, fieldsBySource, initial, presetName }: Props) {
  const router = useRouter()
  const [definition, setDefinition] = useState<ReportDefinition>({
    ...initial,
    name: initial.name || (presetName ? `${presetName} - Custom` : ''),
    columns: initial.columns || [], filters: initial.filters || [], sortDirection: initial.sortDirection || 'asc',
    schedule: { enabled:false, frequency:'daily', timezone:'America/Chicago', hour:8, weekday:1, dayOfMonth:1, recipients:[], deliveryMode:'inline_csv', ...(initial.schedule || {}) },
  })
  const [preview, setPreview] = useState<Preview>(null)
  const [message, setMessage] = useState<{ type:'error'|'success'; text:string } | null>(null)
  const [isPending, startTransition] = useTransition()
  const fields = fieldsBySource[definition.dataSource] || []
  const fieldMap = useMemo(() => new Map(fields.map((f) => [f.key, f])), [fields])

  function changeSource(key: string) {
    const nextFields = fieldsBySource[key] || []
    setDefinition((d) => ({ ...d, dataSource:key, columns: nextFields.filter((f) => f.default).map((f) => f.key), filters:[], sortField:undefined, groupField:undefined }))
    setPreview(null)
  }
  function toggleColumn(key: string) {
    setDefinition((d) => ({ ...d, columns: d.columns.includes(key) ? d.columns.filter((c) => c !== key) : [...d.columns, key] }))
  }
  function addFilter() {
    const first = fields[0]
    if (!first) return
    setDefinition((d) => ({ ...d, filters:[...d.filters, { field:first.key, operator:operators[first.type]?.[0]?.value || 'equals', value:'' }] }))
  }
  function updateFilter(index:number, patch: Partial<ReportFilter>) {
    setDefinition((d) => ({ ...d, filters:d.filters.map((f,i) => {
      if (i !== index) return f
      const next = { ...f, ...patch }
      if (patch.field) {
        const ft = fieldMap.get(patch.field)?.type || 'text'
        next.operator = operators[ft]?.[0]?.value || 'equals'; next.value = ''
      }
      return next
    }) }))
  }
  function removeFilter(index:number) { setDefinition((d) => ({ ...d, filters:d.filters.filter((_,i) => i !== index) })) }
  function recipientText() { return (definition.schedule?.recipients || []).join('\n') }
  function setRecipients(text:string) { setDefinition((d) => ({ ...d, schedule:{ ...d.schedule, recipients:text.split(/[\n,;]+/).map((v) => v.trim()).filter(Boolean) } })) }

  function previewNow() {
    setMessage(null)
    startTransition(async () => {
      const result = await previewReportAction(definition)
      if (!result.ok) { setMessage({ type:'error', text:result.error }); return }
      setPreview({ rows:result.rows, fields:result.fields, columns:result.columns, totalRows:result.totalRows })
    })
  }
  function saveNow() {
    setMessage(null)
    startTransition(async () => {
      const result = await saveReportAction(definition)
      if (!result.ok) { setMessage({ type:'error', text:result.error }); return }
      setMessage({ type:'success', text:'Report saved.' })
      router.push(`/reports/${result.id}`)
      router.refresh()
    })
  }

  const schedule = definition.schedule || {}
  const groupField = definition.groupField

  return <div className="report-builder-layout">
    <div className="report-builder-controls">
      {message && <div className={`banner ${message.type === 'error' ? 'danger' : 'success'}`}><div><strong>{message.type === 'error' ? 'Report action failed' : 'Saved'}</strong><span>{message.text}</span></div></div>}

      <section className="form-card report-builder-card">
        <div className="form-card-heading"><div><span>Report</span><h2>Definition</h2></div></div>
        <div className="form-grid two">
          <label className="field"><span>Name *</span><input value={definition.name || ''} onChange={(e) => setDefinition((d) => ({ ...d, name:e.target.value }))} placeholder="My custom report" /></label>
          <label className="field"><span>Report dataset *</span><select value={definition.dataSource} onChange={(e) => changeSource(e.target.value)}>{sources.map((s) => <option key={s.key} value={s.key}>{s.label}</option>)}</select></label>
          <label className="field span-full"><span>Description</span><textarea rows={2} value={definition.description || ''} onChange={(e) => setDefinition((d) => ({ ...d, description:e.target.value }))} placeholder="Optional description for other administrators." /></label>
        </div>
        <p className="helper-copy">{sources.find((s) => s.key === definition.dataSource)?.description} Combined datasets join related modules at a safe record grain so one-to-many relationships do not create accidental duplicate rows.</p>
      </section>

      <section className="form-card report-builder-card">
        <div className="form-card-heading"><div><span>Columns</span><h2>Choose report fields</h2></div><div className="compact-actions"><button type="button" className="text-button" onClick={() => setDefinition((d) => ({ ...d, columns:fields.map((f) => f.key) }))}>Select all</button><button type="button" className="text-button" onClick={() => setDefinition((d) => ({ ...d, columns:[] }))}>Clear</button></div></div>
        <div className="report-field-grid">{fields.map((field) => <label className="report-field-option" key={field.key}><input type="checkbox" checked={definition.columns.includes(field.key)} onChange={() => toggleColumn(field.key)} /><span>{field.label}{field.module && <small>{moduleLabel(field.module)}</small>}</span></label>)}</div>
      </section>

      <section className="form-card report-builder-card">
        <div className="form-card-heading"><div><span>Filters</span><h2>Limit the results</h2></div><button type="button" className="secondary-button small" onClick={addFilter}>Add filter</button></div>
        {definition.filters.length === 0 ? <div className="empty-inline">No filters. The report will include every record within your access scope.</div> : <div className="report-filter-list">{definition.filters.map((filter, index) => {
          const field = fieldMap.get(filter.field) || fields[0]
          const ops = operators[field?.type || 'text'] || operators.text
          const noValue = ['is_empty','not_empty'].includes(filter.operator)
          return <div className="report-filter-row" key={`${index}-${filter.field}`}>
            <select value={filter.field} onChange={(e) => updateFilter(index, { field:e.target.value })}>{fields.map((f) => <option key={f.key} value={f.key}>{f.label}</option>)}</select>
            <select value={filter.operator} onChange={(e) => updateFilter(index, { operator:e.target.value })}>{ops.map((op) => <option key={op.value} value={op.value}>{op.label}</option>)}</select>
            {!noValue && (field?.type === 'boolean' ? <select value={filter.value || 'true'} onChange={(e) => updateFilter(index, { value:e.target.value })}><option value="true">Yes</option><option value="false">No</option></select> : <input type={field?.type === 'date' ? 'date' : field?.type === 'number' ? 'number' : 'text'} value={filter.value || ''} onChange={(e) => updateFilter(index, { value:e.target.value })} placeholder={filter.operator === 'one_of' ? 'Value 1, Value 2' : 'Value'} />)}
            <button type="button" className="icon-delete" onClick={() => removeFilter(index)} aria-label="Remove filter">×</button>
          </div>
        })}</div>}
      </section>

      <section className="form-card report-builder-card">
        <div className="form-card-heading"><div><span>Organization</span><h2>Sort and group</h2></div></div>
        <div className="form-grid three">
          <label className="field"><span>Sort field</span><select value={definition.sortField || ''} onChange={(e) => setDefinition((d) => ({ ...d, sortField:e.target.value || undefined }))}><option value="">No sorting</option>{fields.map((f) => <option key={f.key} value={f.key}>{f.label}</option>)}</select></label>
          <label className="field"><span>Sort direction</span><select value={definition.sortDirection || 'asc'} onChange={(e) => setDefinition((d) => ({ ...d, sortDirection:e.target.value as 'asc'|'desc' }))}><option value="asc">Ascending</option><option value="desc">Descending</option></select></label>
          <label className="field"><span>Group rows by</span><select value={definition.groupField || ''} onChange={(e) => setDefinition((d) => ({ ...d, groupField:e.target.value || undefined }))}><option value="">No grouping</option>{fields.map((f) => <option key={f.key} value={f.key}>{f.label}</option>)}</select></label>
        </div>
      </section>

      <section className="form-card report-builder-card">
        <div className="form-card-heading"><div><span>Delivery</span><h2>Scheduled email</h2></div><label className="switch-line"><input type="checkbox" checked={!!schedule.enabled} onChange={(e) => setDefinition((d) => ({ ...d, schedule:{ ...d.schedule, enabled:e.target.checked } }))} /><span>Enable schedule</span></label></div>
        <p className="helper-copy">Scheduled reports are regenerated from live data at delivery time. Your current role and agency access are re-checked before every email.</p>
        {schedule.enabled && <>
          <div className="form-grid three">
            <label className="field"><span>Frequency</span><select value={schedule.frequency || 'daily'} onChange={(e) => setDefinition((d) => ({ ...d, schedule:{ ...d.schedule, frequency:e.target.value as any } }))}><option value="daily">Daily</option><option value="weekly">Weekly</option><option value="monthly">Monthly</option></select></label>
            {schedule.frequency === 'weekly' && <label className="field"><span>Day of week</span><select value={schedule.weekday ?? 1} onChange={(e) => setDefinition((d) => ({ ...d, schedule:{ ...d.schedule, weekday:Number(e.target.value) } }))}>{['Sunday','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday'].map((day,i) => <option key={day} value={i}>{day}</option>)}</select></label>}
            {schedule.frequency === 'monthly' && <label className="field"><span>Day of month</span><input type="number" min="1" max="31" value={schedule.dayOfMonth ?? 1} onChange={(e) => setDefinition((d) => ({ ...d, schedule:{ ...d.schedule, dayOfMonth:Number(e.target.value) } }))} /><small>If a month is shorter, the report sends on that month's last day.</small></label>}
            <label className="field"><span>Delivery time</span><select value={schedule.hour ?? 8} onChange={(e) => setDefinition((d) => ({ ...d, schedule:{ ...d.schedule, hour:Number(e.target.value) } }))}>{Array.from({ length:24 },(_,i) => <option key={i} value={i}>{hourLabel(i)}</option>)}</select></label>
            <label className="field"><span>Time zone</span><select value={schedule.timezone || 'America/Chicago'} onChange={(e) => setDefinition((d) => ({ ...d, schedule:{ ...d.schedule, timezone:e.target.value } }))}><option value="America/Chicago">Central Time (Chicago)</option><option value="America/New_York">Eastern Time</option><option value="America/Denver">Mountain Time</option><option value="America/Los_Angeles">Pacific Time</option></select></label>
            <label className="field"><span>Email format</span><select value={schedule.deliveryMode || 'inline_csv'} onChange={(e) => setDefinition((d) => ({ ...d, schedule:{ ...d.schedule, deliveryMode:e.target.value as any } }))}><option value="inline_csv">Table in email + CSV attachment</option><option value="inline">Table in email</option><option value="csv">CSV attachment</option></select></label>
            <label className="field span-full"><span>Recipients *</span><textarea rows={3} value={recipientText()} onChange={(e) => setRecipients(e.target.value)} placeholder="chief@example.org&#10;emscoordinator@example.org" /><small>One address per line or separated by commas. Maximum 25 recipients.</small></label>
          </div>
        </>}
      </section>

      <div className="form-actions report-builder-actions"><button type="button" className="secondary-button" disabled={isPending} onClick={previewNow}>{isPending ? 'Working…' : 'Preview report'}</button><button type="button" className="primary-button" disabled={isPending} onClick={saveNow}>{definition.id ? 'Save changes' : 'Save report'}</button></div>
    </div>

    <aside className="report-preview-panel">
      <div className="report-preview-heading"><div><span>Live preview</span><strong>{preview ? `${preview.totalRows.toLocaleString()} row${preview.totalRows === 1 ? '' : 's'}` : 'Not generated'}</strong></div>{preview && preview.totalRows > preview.rows.length && <small>Showing first {preview.rows.length.toLocaleString()} rows.</small>}</div>
      {!preview ? <div className="empty-state compact"><strong>Preview your report</strong><span>Choose fields and filters, then select Preview report.</span></div> : preview.rows.length === 0 ? <div className="empty-state compact"><strong>No matching records</strong><span>Try changing the report filters.</span></div> : <div className="report-preview-table-wrap"><table className="report-preview-table"><thead><tr>{preview.columns.map((column) => <th key={column}>{preview.fields.find((f) => f.key === column)?.label || column}</th>)}</tr></thead><tbody>{preview.rows.map((row, index) => {
        const groupChanged = groupField && (index === 0 || preview.rows[index-1]?.[groupField] !== row[groupField])
        return <Fragment key={`row-${index}`}>{groupChanged && <tr className="report-group-row"><td colSpan={Math.max(1, preview.columns.length)}>{formatValue(row[groupField!], fieldMap.get(groupField!))}</td></tr>}<tr>{preview.columns.map((column) => <td key={column}>{formatValue(row[column], preview.fields.find((f) => f.key === column))}</td>)}</tr></Fragment>
      })}</tbody></table></div>}
    </aside>
  </div>
}
