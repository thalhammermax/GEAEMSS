import { fieldName, optionList, type RecordFieldDefinition } from '@/lib/record-fields'

type Props = {
  fields: RecordFieldDefinition[]
  values?: Map<string, unknown>
}

function scalarValue(value: unknown) {
  return typeof value === 'string' || typeof value === 'number' ? String(value) : ''
}

export function CustomFieldInputs({ fields, values = new Map() }: Props) {
  const enabled = fields.filter((field) => field.source_type === 'custom' && field.enabled)
  if (enabled.length === 0) return null

  const groups = new Map<string, RecordFieldDefinition[]>()
  for (const field of enabled) {
    const group = field.field_group || 'Additional Information'
    groups.set(group, [...(groups.get(group) ?? []), field])
  }

  return <>
    {[...groups.entries()].map(([group, groupFields]) => <div key={group} className="custom-field-group">
      <div className="form-section-divider"><span>{group}</span></div>
      <div className="form-grid three">
        {groupFields.map((field) => {
          const name = fieldName(field.id)
          const value = values.get(field.id)
          const required = field.required
          const help = field.help_text
          const options = optionList(field)

          if (field.field_type === 'textarea') {
            return <label className="field span-full" key={field.id}><span>{field.label}{required ? ' *' : ''}</span><textarea name={name} rows={3} required={required} defaultValue={scalarValue(value)} placeholder={field.placeholder ?? undefined} />{help && <small>{help}</small>}</label>
          }

          if (field.field_type === 'boolean') {
            return <label className="field checkbox-field" key={field.id}><span>{field.label}</span><span className="checkbox-row"><input name={name} type="checkbox" defaultChecked={value === true} /> Yes</span>{help && <small>{help}</small>}</label>
          }

          if (field.field_type === 'select') {
            return <label className="field" key={field.id}><span>{field.label}{required ? ' *' : ''}</span><select name={name} defaultValue={scalarValue(value)} required={required}><option value="">Select</option>{options.map((option) => <option key={option} value={option}>{option}</option>)}</select>{help && <small>{help}</small>}</label>
          }

          if (field.field_type === 'multiselect') {
            const selected = Array.isArray(value) ? value.filter((item): item is string => typeof item === 'string') : []
            return <label className="field" key={field.id}><span>{field.label}{required ? ' *' : ''}</span><select name={name} multiple defaultValue={selected} required={required} size={Math.min(Math.max(options.length, 3), 7)}>{options.map((option) => <option key={option} value={option}>{option}</option>)}</select>{help && <small>{help}</small>}</label>
          }

          const type = field.field_type === 'phone' ? 'tel' : field.field_type === 'number' ? 'number' : field.field_type
          return <label className="field" key={field.id}><span>{field.label}{required ? ' *' : ''}</span><input name={name} type={type} required={required} defaultValue={scalarValue(value)} placeholder={field.placeholder ?? undefined} />{help && <small>{help}</small>}</label>
        })}
      </div>
    </div>)}
  </>
}
