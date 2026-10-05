import { Fragment } from 'react'
import type { ReportField } from '@/lib/report-catalog'
import { formatDate, formatDateTime } from '@/lib/format'

function formatValue(value:any, field?:ReportField) {
  if (value == null || value === '') return '—'
  if (typeof value === 'boolean') return value ? 'Yes' : 'No'
  if (field?.type === 'date') {
    const raw = String(value)
    return raw.length === 10 ? formatDate(raw) : formatDateTime(raw)
  }
  return String(value)
}

export function ReportTable({ rows, fields, columns, groupField }: { rows:Record<string,any>[]; fields:ReportField[]; columns:string[]; groupField?:string }) {
  const map = new Map(fields.map((f) => [f.key,f]))
  if (!rows.length) return <div className="empty-state"><strong>No records match this report.</strong><span>Change the filters or run the report again later.</span></div>
  return <div className="table-card report-output-table"><table><thead><tr>{columns.map((column) => <th key={column}>{map.get(column)?.label || column}</th>)}</tr></thead><tbody>{rows.map((row,index) => {
    const changed = groupField && (index === 0 || rows[index-1]?.[groupField] !== row[groupField])
    return <Fragment key={`block-${index}`}>{changed && <tr className="report-group-row"><td colSpan={Math.max(1,columns.length)}>{map.get(groupField!)?.label}: {formatValue(row[groupField!], map.get(groupField!))}</td></tr>}<tr>{columns.map((column) => <td key={column}>{formatValue(row[column], map.get(column))}</td>)}</tr></Fragment>
  })}</tbody></table></div>
}
