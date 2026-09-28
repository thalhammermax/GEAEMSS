import type { Metadata } from 'next'
import Link from 'next/link'
import { createClient } from '@/lib/supabase/server'
import { PageHeader } from '@/components/page-header'
import { createCustomField, updateFieldDefinition } from './actions'
import type { EntityType, RecordFieldDefinition } from '@/lib/record-fields'

export const metadata: Metadata = { title: 'Field Configuration' }
type Props = { searchParams: Promise<{ entity?: string; error?: string; saved?: string }> }

const entities: { value: EntityType; label: string; description: string }[] = [
  { value: 'provider', label: 'Personnel', description: 'Provider identity, system and contact fields' },
  { value: 'agency', label: 'Agencies', description: 'Participating agency record fields' },
  { value: 'vehicle', label: 'Vehicles', description: 'Fleet master-record fields' },
]

export default async function FieldConfigurationPage({ searchParams }: Props) {
  const qs = await searchParams
  const entity: EntityType = qs.entity === 'agency' || qs.entity === 'vehicle' ? qs.entity : 'provider'
  const supabase = await createClient()
  const { data, error } = await supabase
    .from('record_field_definitions')
    .select('*')
    .eq('entity_type', entity)
    .order('sort_order')
    .order('label')
  const fields = (data ?? []) as RecordFieldDefinition[]
  const builtins = fields.filter((field) => field.source_type === 'builtin')
  const custom = fields.filter((field) => field.source_type === 'custom')

  return <>
    <PageHeader eyebrow="Administration" title="Field Configuration" description="Choose which fields are used for personnel, agency and vehicle records, and add custom fields without changing the database schema." />
    {qs.saved && <div className="banner success"><div><strong>Saved</strong><span>Field configuration was updated.</span></div></div>}
    {(qs.error || error) && <div className="banner danger"><div><strong>Unable to save</strong><span>{qs.error || error?.message}</span></div></div>}

    <div className="entity-tabs">
      {entities.map((item) => <Link key={item.value} href={`/administration/fields?entity=${item.value}`} className={entity === item.value ? 'entity-tab active' : 'entity-tab'}><strong>{item.label}</strong><span>{item.description}</span></Link>)}
    </div>

    <section className="section-block">
      <div className="section-title"><div><span>{entities.find((item) => item.value === entity)?.label}</span><h2>Built-in fields</h2></div><div className="section-badge">{builtins.filter((f) => f.enabled).length} enabled</div></div>
      <div className="field-config-list">
        {builtins.map((field) => <form action={updateFieldDefinition} className="field-config-row" key={field.id}>
          <input type="hidden" name="id" value={field.id} /><input type="hidden" name="entity_type" value={entity} />
          <div className="field-config-name"><strong>{field.label}</strong><span>{field.field_group} · {field.field_type}{field.system_locked ? ' · Core field' : ''}</span></div>
          <label className="mini-toggle"><input type="checkbox" name="enabled" defaultChecked={field.enabled} disabled={field.system_locked} /><span>Enabled</span></label>
          <label className="mini-toggle"><input type="checkbox" name="required" defaultChecked={field.required} disabled={field.system_locked} /><span>Required</span></label>
          <label className="order-field"><span>Order</span><input type="number" name="sort_order" defaultValue={field.sort_order} /></label>
          <button className="secondary-button small" type="submit">Save</button>
        </form>)}
      </div>
      <p className="configuration-note">Core identity fields stay enabled and required. Disabling any other built-in field hides it from normal record forms but preserves data already stored in that column.</p>
    </section>

    <section className="section-block">
      <div className="section-title"><div><span>Custom fields</span><h2>Additional data</h2></div><div className="section-badge">{custom.length} configured</div></div>
      <div className="field-config-list">
        {custom.length === 0 && <div className="empty-state compact"><strong>No custom fields yet</strong><span>Add the first field below.</span></div>}
        {custom.map((field) => <form action={updateFieldDefinition} className="field-config-row" key={field.id}>
          <input type="hidden" name="id" value={field.id} /><input type="hidden" name="entity_type" value={entity} />
          <div className="field-config-name"><strong>{field.label}</strong><span>{field.field_group} · {field.field_type}</span></div>
          <label className="mini-toggle"><input type="checkbox" name="enabled" defaultChecked={field.enabled} /><span>Enabled</span></label>
          <label className="mini-toggle"><input type="checkbox" name="required" defaultChecked={field.required} /><span>Required</span></label>
          <label className="order-field"><span>Order</span><input type="number" name="sort_order" defaultValue={field.sort_order} /></label>
          <button className="secondary-button small" type="submit">Save</button>
        </form>)}
      </div>
    </section>

    <section className="form-card">
      <div className="form-card-heading"><div><span>Custom field</span><h2>Add a field to {entities.find((item) => item.value === entity)?.label.toLowerCase()}</h2></div></div>
      <form action={createCustomField}>
        <input type="hidden" name="entity_type" value={entity} />
        <div className="form-grid three">
          <label className="field"><span>Field label *</span><input name="label" required placeholder="Station assignment" /></label>
          <label className="field"><span>Field type *</span><select name="field_type" defaultValue="text"><option value="text">Text</option><option value="textarea">Long text</option><option value="number">Number</option><option value="date">Date</option><option value="boolean">Yes / No</option><option value="email">Email</option><option value="phone">Phone</option><option value="url">URL</option><option value="select">Dropdown</option><option value="multiselect">Multi-select</option></select></label>
          <label className="field"><span>Section</span><input name="field_group" defaultValue="Additional Information" /></label>
          <label className="field"><span>Placeholder</span><input name="placeholder" /></label>
          <label className="field span-two"><span>Help text</span><input name="help_text" placeholder="Optional instruction shown below the field" /></label>
          <label className="field span-two"><span>Dropdown options</span><textarea name="options" rows={5} placeholder={'For dropdown or multi-select fields only.\nEnter one option per line.'} /></label>
          <label className="field"><span>Sort order</span><input name="sort_order" type="number" defaultValue="500" /></label>
        </div>
        <div className="inline-options"><label className="checkbox-row"><input type="checkbox" name="enabled" defaultChecked /> Enabled</label><label className="checkbox-row"><input type="checkbox" name="required" /> Required</label></div>
        <div className="form-actions"><button className="primary-button" type="submit">Add custom field</button></div>
      </form>
    </section>
  </>
}
