import type { Metadata } from 'next'
import Link from 'next/link'
import { notFound } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { PageHeader } from '@/components/page-header'
import { NarcoticsSealFields } from '@/components/narcotics-seal-fields'
import { dateInTimeZone, formatQuantity, relationOne } from '@/lib/narcotics'
import { saveNarcoticsCount } from '../../actions'

export const metadata: Metadata = { title: 'Daily Narcotics Count' }
type Props = { params: Promise<{ vehicleId: string }>; searchParams: Promise<{ error?: string; saved?: string }> }

export default async function NarcoticsCountPage({ params, searchParams }: Props) {
  const { vehicleId } = await params
  const qs = await searchParams
  const supabase = await createClient()
  const { data: vehicle } = await supabase
    .from('vehicles')
    .select('id, agency_id, unit_number, fleet_number, narcotics_count_required, agencies(name, short_name), vehicle_types(id, name, narcotics_template_id)')
    .eq('id', vehicleId)
    .maybeSingle()
  if (!vehicle || !vehicle.narcotics_count_required) notFound()

  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return null
  const { data: profile } = await supabase.from('profiles').select('provider_id').eq('id', user.id).maybeSingle()
  const { data: membership } = profile?.provider_id
    ? await supabase.from('provider_agencies').select('id').eq('provider_id', profile.provider_id).eq('agency_id', vehicle.agency_id).eq('active', true).maybeSingle()
    : { data: null }
  if (!membership) return <>
    <PageHeader eyebrow="Narcotics" title="Agency membership required" description="Daily narcotics counts may only be signed by providers who are active members of the apparatus agency."/>
    <div className="banner danger"><div><strong>Count access denied</strong><span>Your login is not linked to an active provider affiliation for this agency.</span></div></div>
    <Link className="secondary-button button-link" href="/narcotics">Back to Narcotics</Link>
  </>

  const { data: setting } = await supabase.from('narcotics_agency_settings').select('*').eq('agency_id', vehicle.agency_id).maybeSingle()
  if (setting?.enabled === false) return <>
    <PageHeader eyebrow="Narcotics" title="Narcotics counts are disabled" description="This agency is not currently accepting portal narcotics counts."/>
    <Link className="secondary-button button-link" href="/narcotics">Back to Narcotics</Link>
  </>

  const agency = relationOne<any>(vehicle.agencies)
  const type = relationOne<any>(vehicle.vehicle_types)
  const templateId = type?.narcotics_template_id ?? null
  const countDate = dateInTimeZone(setting?.timezone || 'America/Chicago')

  if (!templateId) return <>
    <PageHeader eyebrow="Narcotics" title="Count form required" description={`${vehicle.unit_number || vehicle.fleet_number || 'This apparatus'} does not have a narcotics form configured for its vehicle type.`}/>
    <div className="banner warning"><div><strong>Configuration required</strong><span>A System Administrator must assign a daily narcotics form to the {type?.name || 'vehicle'} type.</span></div></div>
    <Link className="secondary-button button-link" href="/narcotics">Back to Narcotics</Link>
  </>

  const [
    { data: template },
    { data: items },
    { data: existing },
    { data: previousSubmitted },
  ] = await Promise.all([
    supabase.from('narcotics_count_templates').select('*').eq('id', templateId).maybeSingle(),
    supabase.from('narcotics_count_template_items').select('*').eq('template_id', templateId).eq('active', true).order('sort_order').order('medication_name'),
    supabase.from('narcotics_counts').select('*').eq('vehicle_id', vehicleId).eq('count_date', countDate).maybeSingle(),
    supabase.from('narcotics_counts').select('seal_number, count_date').eq('vehicle_id', vehicleId).eq('status', 'submitted').lt('count_date', countDate).order('count_date', { ascending: false }).limit(1).maybeSingle(),
  ])

  if (!template) notFound()
  if (existing?.status === 'submitted') return <>
    <PageHeader eyebrow="Narcotics" title="Count already submitted" description={`${vehicle.unit_number || vehicle.fleet_number || 'Vehicle'} · ${countDate}`}/>
    <div className="banner success"><div><strong>Complete</strong><span>This apparatus already has a signed daily count.</span></div></div>
    <Link className="primary-button button-link" href={`/narcotics/${existing.id}`}>View submitted count</Link>
  </>

  const { data: lines } = existing ? await supabase.from('narcotics_count_lines').select('*').eq('count_id', existing.id) : { data: [] as any[] }
  const lineMap = new Map((lines ?? []).map((line: any) => [line.template_item_id, line]))
  const previousSeal = existing?.prior_seal_number || previousSubmitted?.seal_number || null

  return <>
    <PageHeader eyebrow="Daily Narcotics Count" title={vehicle.unit_number || vehicle.fleet_number || 'ALS Apparatus'} description={`${agency?.name || 'Agency'} · ${type?.name || 'Vehicle'} · ${countDate}`} action={<Link className="secondary-button button-link" href="/narcotics">Cancel</Link>} />
    {qs.error && <div className="banner danger"><div><strong>Count was not saved</strong><span>{qs.error}</span></div></div>}
    {qs.saved && <div className="banner success"><div><strong>Draft saved</strong><span>You may return and finish this count later.</span></div></div>}
    <form action={saveNarcoticsCount} className="form-card">
      <input type="hidden" name="vehicle_id" value={vehicleId}/>
      <input type="hidden" name="count_id" value={existing?.id || ''}/>
      <input type="hidden" name="count_date" value={countDate}/>
      <div className="form-card-heading"><div><span>{template.name}</span><h2>Physical inventory</h2></div><span className="pill amber">Unsigned draft</span></div>

      <NarcoticsSealFields previousSeal={previousSeal} initialSeal={existing?.seal_number} initialReason={existing?.seal_change_reason} />

      <div className="narcotics-count-list">{(items ?? []).map((item: any) => {
        const line: any = lineMap.get(item.id)
        return <div className="narcotics-count-row" key={item.id}>
          <input type="hidden" name="item_id" value={item.id}/>
          <div><strong>{item.medication_name}</strong><span>{[item.concentration, item.dosage_form, item.controlled_substance_schedule].filter(Boolean).join(' · ') || 'Controlled substance'}</span></div>
          <div className="expected-count"><span>Expected</span><strong>{formatQuantity(item.expected_quantity)} {item.unit_label}</strong></div>
          <label className="field"><span>Actual *</span><input name={`actual_${item.id}`} type="number" min="0" step="0.001" defaultValue={line?.actual_quantity ?? ''} required/></label>
          <label className="field"><span>Notes</span><input name={`notes_${item.id}`} defaultValue={line?.notes ?? ''} placeholder="Optional"/></label>
        </div>
      })}</div>

      <label className="field"><span>Count notes</span><textarea name="notes" rows={3} defaultValue={existing?.notes ?? ''}/></label>
      <section className="signature-box"><div><span>Electronic signature</span><h3>Sign and submit daily count</h3><p>{setting?.signature_attestation || 'I attest that I personally performed this narcotics inventory count and that the quantities entered are accurate to the best of my knowledge.'}</p></div><label className="field"><span>Type your full name</span><input name="signature_name" autoComplete="name"/></label><label className="checkbox-field"><input type="checkbox" name="attestation"/><span>I agree to the attestation above and electronically sign this count.</span></label></section>
      <div className="form-actions"><button className="secondary-button" type="submit" name="mode" value="draft">Save draft</button><button className="primary-button" type="submit" name="mode" value="submit">Sign & submit</button></div>
    </form>
  </>
}
