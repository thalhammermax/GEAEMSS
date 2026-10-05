export function formatDate(value: string | null | undefined) {
  if (!value) return '—'
  const [year, month, day] = value.split('-').map(Number)
  if (!year || !month || !day) return value
  return new Intl.DateTimeFormat('en-US', {
    month: 'short',
    day: 'numeric',
    year: 'numeric',
    timeZone: 'America/Chicago',
  }).format(new Date(Date.UTC(year, month - 1, day, 12)))
}

export function titleCase(value: string | null | undefined) {
  if (!value) return '—'
  return value.replaceAll('_', ' ').replace(/\b\w/g, (c) => c.toUpperCase())
}


export function formatDateTime(value: string | Date | null | undefined, timeZone = 'America/Chicago') {
  if (!value) return '—'
  const date = value instanceof Date ? value : new Date(value)
  if (Number.isNaN(date.getTime())) return String(value)
  return new Intl.DateTimeFormat('en-US', {
    month: 'short',
    day: 'numeric',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
    hourCycle: 'h23',
    timeZone,
  }).format(date)
}

export function formatHour24(hour: number | string | null | undefined) {
  const parsed = Number(hour)
  if (!Number.isInteger(parsed) || parsed < 0 || parsed > 23) return '—'
  return `${String(parsed).padStart(2, '0')}:00`
}
