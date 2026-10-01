import { createClient } from '@/lib/supabase/server'
import { buildInspectionPdf } from '@/lib/inspection-pdf'
import { normalizeInspectionPdfSettings } from '@/lib/inspection-pdf-settings'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

export async function GET() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return new Response('Authentication required.', { status: 401 })

  const { data: role } = await supabase
    .from('user_roles')
    .select('role')
    .eq('user_id', user.id)
    .eq('role', 'system_admin')
    .maybeSingle()

  if (!role) return new Response('System Administrator access is required.', { status: 403 })

  const { data: settingsRow } = await supabase
    .from('inspection_pdf_template_settings')
    .select('*')
    .eq('id', 'system')
    .maybeSingle()

  const settings = normalizeInspectionPdfSettings(settingsRow)

  const inspection = {
    id: '00000000-0000-0000-0000-000000000000',
    inspection_date: '2026-10-01',
    workflow_status: 'submitted',
    result: 'passed_with_deficiencies',
    next_due_date: '2027-10-01',
    inspector_name: 'Sample Inspector',
    inspector_organization: 'Greater Elgin Area EMS System',
    inspection_location: 'GEAEMS System Office',
    odometer: 42817,
    notes: 'This sample record is generated only to preview the inspection PDF template.',
    submitted_at: '2026-10-01T17:30:00.000Z',
  }

  const vehicle = {
    id: '00000000-0000-0000-0000-000000000001',
    unit_number: 'M61',
    fleet_number: '61',
    year: 2026,
    make: 'Ford',
    model: 'F-550',
    agencies: { name: 'Example Fire District', short_name: 'EFD' },
    vehicle_types: { name: 'GEA ALS Ambulance', code: 'ALS_AMB' },
  }

  const formVersion = { id: 'sample-version', version_number: 3, status: 'published' }
  const template = { id: 'sample-template', name: 'GEA ALS Ambulance Inspection', code: 'GEA_ALS_AMBULANCE' }
  const sections = [
    {
      id: 'sample-section-1',
      title: 'Patient Care Equipment',
      sort_order: 10,
      inspection_form_items: [
        { id: 'sample-item-1', label: 'Portable Oxygen Cylinder', requirement_text: '1 with regulator', response_type: 'compliance', sort_order: 10 },
        { id: 'sample-item-2', label: 'Cardiac Monitor / Defibrillator', requirement_text: '1 operational unit', response_type: 'compliance', sort_order: 20 },
        { id: 'sample-item-3', label: 'Main Oxygen Pressure', requirement_text: 'Record observed PSI', response_type: 'number', sort_order: 30 },
      ],
    },
    {
      id: 'sample-section-2',
      title: 'Safety & Operations',
      sort_order: 20,
      inspection_form_items: [
        { id: 'sample-item-4', label: 'Emergency warning equipment', requirement_text: 'Operational', response_type: 'compliance', sort_order: 10 },
      ],
    },
  ]
  const responses = [
    { form_item_id: 'sample-item-1', status: 'pass', observed_value: '1800 PSI', notes: null },
    { form_item_id: 'sample-item-2', status: 'fail', observed_value: null, notes: 'Spare battery did not pass capacity check.' },
    { form_item_id: 'sample-item-3', status: null, observed_value: '1750', notes: 'Main cylinder pressure at inspection.' },
    { form_item_id: 'sample-item-4', status: 'pass', observed_value: null, notes: null },
  ]
  const deficiencies = [
    {
      id: 'sample-deficiency',
      description: 'Cardiac Monitor / Defibrillator — Required: 1 operational unit — Spare battery did not pass capacity check.',
      severity: 'deficiency',
      status: 'open',
      correction_due_date: '2026-10-08',
      correction_notes: 'Replacement battery ordered; unit remains in service with verified primary battery.',
    },
  ]

  const bytes = await buildInspectionPdf({
    inspection,
    vehicle,
    inspectionType: { name: 'GEAEMS System Vehicle Inspection' },
    formVersion,
    template,
    sections,
    responses,
    deficiencies,
    settings,
  })

  return new Response(Buffer.from(bytes), {
    headers: {
      'Content-Type': 'application/pdf',
      'Content-Disposition': 'inline; filename="GEAEMS-Inspection-PDF-Template-Preview.pdf"',
      'Cache-Control': 'private, no-store, max-age=0',
    },
  })
}
