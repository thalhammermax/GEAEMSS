import { PDFDocument, StandardFonts, degrees, rgb, type PDFFont, type PDFPage } from 'pdf-lib'
import { normalizeInspectionPdfSettings, type InspectionPdfSettings } from '@/lib/inspection-pdf-settings'

export type InspectionPdfData = {
  inspection: any
  vehicle: any
  inspectionType?: any
  formVersion?: any
  template?: any
  sections?: any[]
  responses?: any[]
  deficiencies?: any[]
  settings?: Partial<InspectionPdfSettings> | null
}

const PAGE_WIDTH = 612
const PAGE_HEIGHT = 792
const MARGIN = 42
const CONTENT_WIDTH = PAGE_WIDTH - MARGIN * 2
const BOTTOM = 48


function pdfColor(hex: string, fallback = '#14314A') {
  const value = /^#[0-9A-Fa-f]{6}$/.test(hex) ? hex : fallback
  const red = Number.parseInt(value.slice(1, 3), 16) / 255
  const green = Number.parseInt(value.slice(3, 5), 16) / 255
  const blue = Number.parseInt(value.slice(5, 7), 16) / 255
  return rgb(red, green, blue)
}

function one<T = any>(value: T | T[] | null | undefined): T | null {
  return Array.isArray(value) ? (value[0] ?? null) : (value ?? null)
}

function safe(value: unknown) {
  if (value == null) return ''
  return String(value)
    .replace(/[\u2012\u2013\u2014\u2212]/g, '-')
    .replace(/[\u2018\u2019]/g, "'")
    .replace(/[\u201c\u201d]/g, '"')
    .replace(/\u2026/g, '...')
    .replace(/\u00a0/g, ' ')
    .replace(/[^\x09\x0A\x0D\x20-\x7E\xA0-\xFF]/g, '?')
}

function date(value: unknown) {
  if (!value) return '—'
  const raw = String(value)
  const parsed = /^\d{4}-\d{2}-\d{2}$/.test(raw) ? new Date(`${raw}T12:00:00`) : new Date(raw)
  if (Number.isNaN(parsed.getTime())) return safe(raw)
  return parsed.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric', timeZone: 'America/Chicago' })
}

function dateTime(value: unknown) {
  if (!value) return '—'
  const parsed = new Date(String(value))
  if (Number.isNaN(parsed.getTime())) return safe(value)
  return parsed.toLocaleString('en-US', { month: 'short', day: 'numeric', year: 'numeric', hour: '2-digit', minute: '2-digit', hourCycle: 'h23', timeZone: 'America/Chicago' })
}

function titleCase(value: unknown) {
  const text = safe(value || '')
  return text ? text.replace(/_/g, ' ').replace(/\b\w/g, (m) => m.toUpperCase()) : '—'
}

function wrapText(font: PDFFont, text: string, size: number, maxWidth: number) {
  const normalized = safe(text).replace(/\s+/g, ' ').trim()
  if (!normalized) return ['']
  const words = normalized.split(' ')
  const lines: string[] = []
  let line = ''

  for (const word of words) {
    const candidate = line ? `${line} ${word}` : word
    if (font.widthOfTextAtSize(candidate, size) <= maxWidth) {
      line = candidate
      continue
    }

    if (line) lines.push(line)
    if (font.widthOfTextAtSize(word, size) <= maxWidth) {
      line = word
      continue
    }

    let fragment = ''
    for (const char of word) {
      const next = fragment + char
      if (fragment && font.widthOfTextAtSize(next, size) > maxWidth) {
        lines.push(fragment)
        fragment = char
      } else {
        fragment = next
      }
    }
    line = fragment
  }

  if (line) lines.push(line)
  return lines.length ? lines : ['']
}

export async function buildInspectionPdf(data: InspectionPdfData) {
  const settings = normalizeInspectionPdfSettings(data.settings)
  const accent = pdfColor(settings.accentColor)
  const headingFill = pdfColor(settings.headingFillColor, '#EDF2F7')
  const pdf = await PDFDocument.create()
  pdf.setTitle(`${safe(settings.reportTitle)} - ${safe(data.vehicle?.unit_number || data.vehicle?.fleet_number || data.inspection?.id)}`)
  pdf.setAuthor(safe(settings.organizationName))
  pdf.setSubject(safe(settings.reportTitle))
  pdf.setCreator('GEAEMS Portal')

  const regular = await pdf.embedFont(StandardFonts.Helvetica)
  const bold = await pdf.embedFont(StandardFonts.HelveticaBold)
  const agency = one<any>(data.vehicle?.agencies)
  const vehicleType = one<any>(data.vehicle?.vehicle_types)
  const unit = safe(data.vehicle?.unit_number || data.vehicle?.fleet_number || 'Vehicle')
  const agencyName = safe(agency?.name || agency?.short_name || '')
  const result = data.inspection?.workflow_status === 'draft'
    ? 'DRAFT'
    : titleCase(data.inspection?.result || data.inspection?.workflow_status || 'Submitted')

  let page!: PDFPage
  let y = 0

  const addPage = () => {
    page = pdf.addPage([PAGE_WIDTH, PAGE_HEIGHT])
    page.drawText(safe(settings.organizationName), {
      x: MARGIN,
      y: PAGE_HEIGHT - 36,
      size: 10,
      font: bold,
      color: accent,
    })
    page.drawText(safe(settings.reportTitle), {
      x: MARGIN,
      y: PAGE_HEIGHT - 51,
      size: 8,
      font: regular,
      color: rgb(0.38, 0.43, 0.48),
    })

    const right = `${unit}${agencyName ? ` · ${agencyName}` : ''}`
    const rightWidth = regular.widthOfTextAtSize(right, 8)
    page.drawText(right, {
      x: Math.max(MARGIN, PAGE_WIDTH - MARGIN - rightWidth),
      y: PAGE_HEIGHT - 45,
      size: 8,
      font: regular,
      color: rgb(0.38, 0.43, 0.48),
    })
    page.drawLine({
      start: { x: MARGIN, y: PAGE_HEIGHT - 60 },
      end: { x: PAGE_WIDTH - MARGIN, y: PAGE_HEIGHT - 60 },
      thickness: 0.8,
      color: rgb(0.78, 0.82, 0.85),
    })
    y = PAGE_HEIGHT - 82
  }

  const ensure = (height: number) => {
    if (y - height < BOTTOM) addPage()
  }

  const drawWrapped = (
    text: unknown,
    x: number,
    width: number,
    size = 9,
    font = regular,
    lineHeight = size + 3,
    color = rgb(0.12, 0.14, 0.16)
  ) => {
    const lines = wrapText(font, safe(text), size, width)
    ensure(lines.length * lineHeight)
    for (const line of lines) {
      page.drawText(line, { x, y, size, font, color })
      y -= lineHeight
    }
    return lines.length
  }

  const heading = (text: string) => {
    ensure(32)
    y -= 4
    page.drawRectangle({
      x: MARGIN,
      y: y - 17,
      width: CONTENT_WIDTH,
      height: 22,
      color: headingFill,
    })
    page.drawText(safe(text), {
      x: MARGIN + 9,
      y: y - 10,
      size: 10,
      font: bold,
      color: accent,
    })
    y -= 31
  }

  const kv = (label: string, value: unknown, x: number, width: number) => {
    const valueText = safe(value || '—')
    const lines = wrapText(regular, valueText, 9, width)
    ensure(14 + lines.length * 12)
    page.drawText(safe(label).toUpperCase(), {
      x,
      y,
      size: 7,
      font: bold,
      color: rgb(0.42, 0.47, 0.52),
    })
    y -= 12
    for (const line of lines) {
      page.drawText(line, {
        x,
        y,
        size: 9,
        font: regular,
        color: rgb(0.1, 0.12, 0.14),
      })
      y -= 12
    }
    y -= 4
  }

  addPage()

  page.drawText(unit, {
    x: MARGIN,
    y,
    size: 20,
    font: bold,
    color: accent,
  })

  const badgeColor = data.inspection?.workflow_status === 'draft'
    ? rgb(0.77, 0.48, 0.08)
    : data.inspection?.result === 'passed'
      ? rgb(0.12, 0.48, 0.28)
      : data.inspection?.result === 'passed_with_deficiencies'
        ? rgb(0.77, 0.48, 0.08)
        : rgb(0.69, 0.16, 0.17)

  if (settings.showResultBadge) {
    const badgeWidth = Math.max(72, bold.widthOfTextAtSize(result, 8) + 20)
    page.drawRectangle({
      x: PAGE_WIDTH - MARGIN - badgeWidth,
      y: y - 4,
      width: badgeWidth,
      height: 20,
      color: badgeColor,
    })
    page.drawText(result, {
      x: PAGE_WIDTH - MARGIN - badgeWidth + 10,
      y: y + 2,
      size: 8,
      font: bold,
      color: rgb(1, 1, 1),
    })
  }
  y -= 23

  if (settings.showVehicleDetails) {
    drawWrapped(
      [
        agencyName,
        [data.vehicle?.year, data.vehicle?.make, data.vehicle?.model].filter(Boolean).join(' '),
        vehicleType?.name,
      ].filter(Boolean).join(' · '),
      MARGIN,
      CONTENT_WIDTH,
      9,
      regular,
      12,
      rgb(0.35, 0.4, 0.44)
    )
    y -= 8
  } else {
    y -= 8
  }

  if (settings.showSummary) {
    heading(settings.summaryHeading)

    const leftX = MARGIN
    const rightX = MARGIN + CONTENT_WIDTH / 2 + 8
    const colW = CONTENT_WIDTH / 2 - 16
    const leftItems: [string, unknown][] = [
      ['Inspection date', date(data.inspection?.inspection_date)],
      ['Inspection type', data.inspectionType?.name || data.template?.name || '—'],
      ...(settings.showFormVersion ? [['Inspection form', data.template ? `${data.template.name} · Version ${data.formVersion?.version_number ?? '—'}` : 'Legacy inspection'] as [string, unknown]] : []),
      ['Inspector', data.inspection?.inspector_name || '—'],
    ]
    const rightItems: [string, unknown][] = [
      ['Location', data.inspection?.inspection_location || '—'],
      ['Odometer', data.inspection?.odometer ?? '—'],
      ...(settings.showSubmittedAt ? [['Submitted', dateTime(data.inspection?.submitted_at)] as [string, unknown]] : []),
      ...(settings.showInspectionId ? [['Inspection ID', data.inspection?.id || '—'] as [string, unknown]] : []),
    ]

    const startY = y
    let leftY = startY
    for (const [label, value] of leftItems) {
      y = leftY
      kv(label, value, leftX, colW)
      leftY = y
    }
    let rightY = startY
    for (const [label, value] of rightItems) {
      y = rightY
      kv(label, value, rightX, colW)
      rightY = y
    }
    y = Math.min(leftY, rightY) - 2
  }

  if (settings.showOverallNotes && data.inspection?.notes) {
    heading(settings.notesHeading)
    drawWrapped(data.inspection.notes, MARGIN, CONTENT_WIDTH, 9, regular, 12)
    y -= 6
  }

  const responses = new Map((data.responses ?? []).map((r: any) => [r.form_item_id, r]))

  if (settings.showChecklist && data.formVersion && (data.sections ?? []).length) {
    heading(settings.checklistHeading)

    for (const section of [...(data.sections ?? [])].sort((a: any, b: any) => Number(a.sort_order) - Number(b.sort_order))) {
      ensure(28)
      page.drawText(safe(section.title), {
        x: MARGIN,
        y,
        size: 12,
        font: bold,
        color: accent,
      })
      y -= 18

      const items = [...(section.inspection_form_items ?? [])]
        .sort((a: any, b: any) => Number(a.sort_order) - Number(b.sort_order))

      for (let index = 0; index < items.length; index++) {
        const item = items[index]
        const response: any = responses.get(item.id) || {}
        const responseType = item.response_type || 'compliance'
        const status = responseType === 'compliance'
          ? response.status === 'pass'
            ? 'COMPLIANT'
            : response.status === 'fail'
              ? 'DEFICIENT'
              : response.status === 'na'
                ? 'N/A'
                : 'NOT ANSWERED'
          : safe(response.observed_value || 'NOT ANSWERED').toUpperCase()

        const statusColor = response.status === 'fail'
          ? rgb(0.69, 0.16, 0.17)
          : response.status === 'pass'
            ? rgb(0.12, 0.48, 0.28)
            : rgb(0.42, 0.47, 0.52)

        const labelLines = wrapText(bold, `${index + 1}. ${safe(item.label)}`, 9, 365)
        const reqLines = settings.showRequirements ? wrapText(regular, `Required: ${safe(item.requirement_text)}`, 8, 365) : []
        const observedLines = settings.showObservedValues && response.observed_value
          ? wrapText(regular, responseType === 'compliance' ? `Observed / count: ${safe(response.observed_value)}` : `Response: ${safe(response.observed_value)}`, 8, 365)
          : []
        const noteLines = settings.showItemNotes && response.notes
          ? wrapText(regular, `Notes: ${safe(response.notes)}`, 8, 365)
          : []

        const blockHeight =
          10 +
          labelLines.length * 12 +
          reqLines.length * 10 +
          observedLines.length * 10 +
          noteLines.length * 10 +
          12

        ensure(blockHeight)
        const topY = y

        for (const line of labelLines) {
          page.drawText(line, { x: MARGIN + 7, y, size: 9, font: bold, color: rgb(0.1, 0.12, 0.14) })
          y -= 12
        }
        for (const line of reqLines) {
          page.drawText(line, { x: MARGIN + 7, y, size: 8, font: regular, color: rgb(0.38, 0.43, 0.48) })
          y -= 10
        }
        for (const line of observedLines) {
          page.drawText(line, { x: MARGIN + 7, y, size: 8, font: regular, color: rgb(0.18, 0.21, 0.24) })
          y -= 10
        }
        for (const line of noteLines) {
          page.drawText(line, { x: MARGIN + 7, y, size: 8, font: regular, color: rgb(0.18, 0.21, 0.24) })
          y -= 10
        }

        const statusWidth = 136
        page.drawRectangle({
          x: PAGE_WIDTH - MARGIN - statusWidth,
          y: topY - 14,
          width: statusWidth,
          height: 18,
          borderWidth: 0.8,
          borderColor: statusColor,
          color: rgb(1, 1, 1),
        })
        const textWidth = bold.widthOfTextAtSize(status, 7)
        page.drawText(status, {
          x: PAGE_WIDTH - MARGIN - statusWidth + Math.max(8, (statusWidth - textWidth) / 2),
          y: topY - 8,
          size: 7,
          font: bold,
          color: statusColor,
        })

        y -= 4
        page.drawLine({
          start: { x: MARGIN, y },
          end: { x: PAGE_WIDTH - MARGIN, y },
          thickness: 0.4,
          color: rgb(0.86, 0.88, 0.9),
        })
        y -= 8
      }
      y -= 5
    }
  }

  if (settings.showDeficiencies && (data.deficiencies ?? []).length) {
    heading(settings.deficienciesHeading)

    for (const [index, deficiency] of (data.deficiencies ?? []).entries()) {
      const desc = wrapText(bold, `${index + 1}. ${safe(deficiency.description)}`, 9, CONTENT_WIDTH - 12)
      const meta =
        `${titleCase(deficiency.severity)} · ${titleCase(deficiency.status)}` +
        (deficiency.correction_due_date ? ` · Due ${date(deficiency.correction_due_date)}` : '')
      const notes = settings.showCorrectionNotes && deficiency.correction_notes
        ? wrapText(regular, `Correction notes: ${safe(deficiency.correction_notes)}`, 8, CONTENT_WIDTH - 12)
        : []

      ensure(desc.length * 12 + 12 + notes.length * 10 + 14)

      for (const line of desc) {
        page.drawText(line, { x: MARGIN + 6, y, size: 9, font: bold, color: rgb(0.1, 0.12, 0.14) })
        y -= 12
      }
      page.drawText(meta, { x: MARGIN + 6, y, size: 8, font: regular, color: rgb(0.55, 0.24, 0.16) })
      y -= 12
      for (const line of notes) {
        page.drawText(line, { x: MARGIN + 6, y, size: 8, font: regular, color: rgb(0.3, 0.34, 0.38) })
        y -= 10
      }
      page.drawLine({
        start: { x: MARGIN, y: y - 2 },
        end: { x: PAGE_WIDTH - MARGIN, y: y - 2 },
        thickness: 0.4,
        color: rgb(0.86, 0.88, 0.9),
      })
      y -= 10
    }
  }

  const generated = new Date().toLocaleString('en-US', { month: 'short', day: 'numeric', year: 'numeric', hour: '2-digit', minute: '2-digit', hourCycle: 'h23', timeZone: 'America/Chicago' })
  const pages = pdf.getPages()

  pages.forEach((pdfPage, index) => {
    if (settings.showDraftWatermark && data.inspection?.workflow_status === 'draft') {
      pdfPage.drawText('DRAFT', {
        x: 175,
        y: 350,
        size: 72,
        font: bold,
        color: rgb(0.55, 0.58, 0.61),
        opacity: 0.09,
        rotate: degrees(35),
      })
    }

    const footerParts = [safe(settings.footerText)]
    if (settings.showGenerationTimestamp) footerParts.push(generated)
    if (settings.showInspectionId) footerParts.push(`Inspection ${safe(data.inspection?.id)}`)
    const footer = footerParts.filter(Boolean).join(' · ')
    if (footer) {
      pdfPage.drawText(footer, {
        x: MARGIN,
        y: 24,
        size: 6.5,
        font: regular,
        color: rgb(0.46, 0.5, 0.54),
      })
    }

    if (settings.showPageNumbers) {
      const pageText = `Page ${index + 1} of ${pages.length}`
      const width = regular.widthOfTextAtSize(pageText, 6.5)
      pdfPage.drawText(pageText, {
        x: PAGE_WIDTH - MARGIN - width,
        y: 24,
        size: 6.5,
        font: regular,
        color: rgb(0.46, 0.5, 0.54),
      })
    }
  })

  return pdf.save()
}
