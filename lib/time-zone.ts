export function localDateTimeToUtc(localValue: string, timeZone = 'America/Chicago') {
  const match = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})$/.exec(localValue)
  if (!match) throw new Error('A valid date and time is required.')
  const [, y, m, d, hh, mm] = match
  const wallClockAsUtc = Date.UTC(Number(y), Number(m) - 1, Number(d), Number(hh), Number(mm), 0)

  const formatter = new Intl.DateTimeFormat('en-US', {
    timeZone,
    year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit', second: '2-digit', hourCycle: 'h23',
  })
  const offsetAt = (timestamp: number) => {
    const parts = Object.fromEntries(formatter.formatToParts(new Date(timestamp)).filter((p) => p.type !== 'literal').map((p) => [p.type, p.value]))
    const represented = Date.UTC(Number(parts.year), Number(parts.month) - 1, Number(parts.day), Number(parts.hour), Number(parts.minute), Number(parts.second))
    return represented - timestamp
  }

  let instant = wallClockAsUtc - offsetAt(wallClockAsUtc)
  instant = wallClockAsUtc - offsetAt(instant)
  return new Date(instant).toISOString()
}

export function formatInTimeZone(value: string | Date, timeZone = 'America/Chicago', options?: Intl.DateTimeFormatOptions) {
  return new Intl.DateTimeFormat('en-US', {
    timeZone,
    dateStyle: 'medium',
    timeStyle: 'short',
    ...options,
  }).format(typeof value === 'string' ? new Date(value) : value)
}

export function dateTimeLocalValue(value: string | Date, timeZone = 'America/Chicago') {
  const formatter = new Intl.DateTimeFormat('en-CA', {
    timeZone,
    year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', hourCycle: 'h23',
  })
  const parts = Object.fromEntries(formatter.formatToParts(typeof value === 'string' ? new Date(value) : value).filter((p) => p.type !== 'literal').map((p) => [p.type, p.value]))
  return `${parts.year}-${parts.month}-${parts.day}T${parts.hour}:${parts.minute}`
}
