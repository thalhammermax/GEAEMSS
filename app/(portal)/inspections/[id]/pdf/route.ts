import { createClient } from '@/lib/supabase/server'
import { buildInspectionPdf } from '@/lib/inspection-pdf'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

type Context = { params: Promise<{ id: string }> }

function one<T = any>(value: T | T[] | null | undefined): T | null {
  return Array.isArray(value) ? (value[0] ?? null) : (value ?? null)
}

function filenamePart(value: unknown) {
  return String(value || 'Vehicle')
    .replace(/[^a-zA-Z0-9._-]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 80) || 'Vehicle'
}

export async function GET(_request: Request, { params }: Context) {
  const { id } = await params
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()

  if (!user) {
    return new Response('Authentication required.', { status: 401 })
  }

  const { data: inspection, error } = await supabase
    .from('vehicle_inspections')
    .select('id, vehicle_id, inspection_type_id, inspection_date, workflow_status, result, next_due_date, inspector_name, inspector_organization, inspection_location, odometer, notes, submitted_at, form_version_id, vehicles(id, agency_id, unit_number, fleet_number, year, make, model, vin, license_plate, license_plate_state, agencies(name, short_name), vehicle_types(name, code)), inspection_types(name)')
    .eq('id', id)
    .maybeSingle()

  if (error || !inspection) {
    return new Response('Inspection not found or not available to your account.', { status: 404 })
  }

  const vehicle = one<any>(inspection.vehicles)
  const inspectionType = one<any>(inspection.inspection_types)

  const { data: deficiencies } = await supabase
    .from('vehicle_inspection_deficiencies')
    .select('id, form_item_id, description, severity, status, correction_due_date, correction_notes, created_at')
    .eq('vehicle_inspection_id', id)
    .order('created_at')

  const { data: pdfSettings } = await supabase
    .from('inspection_pdf_template_settings')
    .select('*')
    .eq('id', 'system')
    .maybeSingle()

  let formVersion: any = null
  let template: any = null
  let sections: any[] = []
  let responses: any[] = []

  if (inspection.form_version_id) {
    const [{ data: version }, { data: responseRows }] = await Promise.all([
      supabase
        .from('inspection_form_versions')
        .select('id, template_id, version_number, status')
        .eq('id', inspection.form_version_id)
        .maybeSingle(),
      supabase
        .from('inspection_item_responses')
        .select('id, form_item_id, status, observed_value, notes')
        .eq('vehicle_inspection_id', id),
    ])

    formVersion = version
    responses = responseRows ?? []

    if (formVersion) {
      const [{ data: templateRow }, { data: sectionRows }] = await Promise.all([
        supabase
          .from('inspection_form_templates')
          .select('id, code, name, scope_type, agency_id, vehicle_type_id')
          .eq('id', formVersion.template_id)
          .maybeSingle(),
        supabase
          .from('inspection_form_sections')
          .select('id, title, sort_order, inspection_form_items(id, item_code, label, requirement_text, response_type, allow_na, required, failure_severity, requires_comment_on_fail, sort_order)')
          .eq('form_version_id', formVersion.id)
          .order('sort_order'),
      ])

      template = templateRow
      sections = sectionRows ?? []
    }
  }

  const bytes = await buildInspectionPdf({
    inspection,
    vehicle,
    inspectionType,
    formVersion,
    template,
    sections,
    responses,
    deficiencies: deficiencies ?? [],
    settings: pdfSettings,
  })

  const unit = filenamePart(vehicle?.unit_number || vehicle?.fleet_number || 'Vehicle')
  const inspectionDate = filenamePart(inspection.inspection_date || 'Inspection')
  const filename = `GEAEMS-Inspection-${unit}-${inspectionDate}.pdf`

  return new Response(Buffer.from(bytes), {
    headers: {
      'Content-Type': 'application/pdf',
      'Content-Disposition': `attachment; filename="${filename}"`,
      'Cache-Control': 'private, no-store, max-age=0',
    },
  })
}
