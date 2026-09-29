'use client'

import { useRef } from 'react'

type Item = {
  id: string
  label: string
  requirement_text: string
  allow_na: boolean
  required: boolean
}

type Response = { status?: string | null; observed_value?: string | null; notes?: string | null }

export function InspectionSection({ title, items, responses, readOnly = false }: {
  title: string
  items: Item[]
  responses: Record<string, Response>
  readOnly?: boolean
}) {
  const ref = useRef<HTMLDivElement>(null)

  function markAllCompliant() {
    ref.current?.querySelectorAll<HTMLInputElement>('input[data-pass="true"]').forEach((input) => { input.checked = true })
  }

  return <section className="inspection-section" ref={ref}>
    <div className="inspection-section-heading">
      <div><span>Inspection section</span><h2>{title}</h2></div>
      {!readOnly && <button className="secondary-button small" type="button" onClick={markAllCompliant}>Mark section compliant</button>}
    </div>
    <div className="inspection-items">
      {items.map((item, index) => {
        const response = responses[item.id] ?? {}
        const status = response.status ?? ''
        return <div className={`inspection-item${status === 'fail' ? ' deficient' : status === 'pass' ? ' compliant' : ''}`} key={item.id}>
          <input type="hidden" name="form_item_id" value={item.id} />
          <div className="inspection-item-number">{index + 1}</div>
          <div className="inspection-item-copy">
            <strong>{item.label}</strong>
            <span>Required: {item.requirement_text}</span>
          </div>
          <div className="inspection-response-options">
            {readOnly ? <span className={`pill ${status === 'pass' ? 'green' : status === 'fail' ? 'red' : ''}`}>{status === 'pass' ? 'Compliant' : status === 'fail' ? 'Deficient' : status === 'na' ? 'N/A' : 'Not answered'}</span> : <>
              <label className="inspection-choice pass"><input data-pass="true" type="radio" name={`status_${item.id}`} value="pass" defaultChecked={status === 'pass'} required={item.required} /><span>Compliant</span></label>
              <label className="inspection-choice fail"><input type="radio" name={`status_${item.id}`} value="fail" defaultChecked={status === 'fail'} required={item.required} /><span>Deficient</span></label>
              {item.allow_na && <label className="inspection-choice"><input type="radio" name={`status_${item.id}`} value="na" defaultChecked={status === 'na'} required={item.required} /><span>N/A</span></label>}
            </>}
          </div>
          <div className="inspection-item-detail">
            <label><span>Observed / count</span>{readOnly ? <strong>{response.observed_value || '—'}</strong> : <input name={`observed_${item.id}`} defaultValue={response.observed_value ?? ''} placeholder="Optional" />}</label>
            <label><span>Notes</span>{readOnly ? <strong>{response.notes || '—'}</strong> : <input name={`notes_${item.id}`} defaultValue={response.notes ?? ''} placeholder="Required details if deficient, when applicable" />}</label>
          </div>
        </div>
      })}
    </div>
  </section>
}
