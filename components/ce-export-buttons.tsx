'use client'

type Row = Record<string, string | number | null | undefined>
type Column = { key: string; label: string }

export function CEExportButtons({ rows, columns, filename }: { rows: Row[]; columns: Column[]; filename: string }) {
  function downloadCsv() {
    const escape = (value: unknown) => {
      const text = value == null ? '' : String(value)
      return /[",\n\r]/.test(text) ? `"${text.replace(/"/g, '""')}"` : text
    }
    const csv = [columns.map((c) => escape(c.label)).join(','), ...rows.map((row) => columns.map((c) => escape(row[c.key])).join(','))].join('\r\n')
    const blob = new Blob([csv], { type: 'text/csv;charset=utf-8' })
    const url = URL.createObjectURL(blob)
    const anchor = document.createElement('a')
    anchor.href = url
    anchor.download = filename.endsWith('.csv') ? filename : `${filename}.csv`
    document.body.appendChild(anchor)
    anchor.click()
    anchor.remove()
    URL.revokeObjectURL(url)
  }

  return <div className="header-actions"><button className="secondary-button small" type="button" onClick={downloadCsv}>Download CSV roster</button><button className="secondary-button small" type="button" onClick={() => window.print()}>Print roster</button></div>
}
