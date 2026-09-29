'use client'

import { useRef } from 'react'

type Item = {
  id: string
  label: string
  requirement_text: string
  response_type?: 'compliance' | 'text' | 'number' | 'date' | 'yes_no'
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
      {!readOnly && items.some((item) => (item.response_type ?? 'compliance') === 'compliance') && <button className="secondary-button small" type="button" onClick={markAllCompliant}>Mark section compliant</button>}
    </div>
    <div className="inspection-items">
      {items.map((item, index) => {
        const response = responses[item.id] ?? {}
        const status = response.status ?? ''
        const responseType = item.response_type ?? 'compliance'
        const itemClass = responseType === 'compliance' ? (status === 'fail' ? ' deficient' : status === 'pass' ? ' compliant' : '') : ''
        return <div className={`inspection-item${itemClass}`} key={item.id}>
          <input type="hidden" name="form_item_id" value={item.id} />
          <div className="inspection-item-number">{index + 1}</div>
          <div className="inspection-item-copy">
            <strong>{item.label}</strong>
            <span>Required: {item.requirement_text}</span>
          </div>
          <div className="inspection-response-options">
            {responseType === 'compliance' ? (readOnly ? <span className={`pill ${status === 'pass' ? 'green' : status === 'fail' ? 'red' : ''}`}>{status === 'pass' ? 'Compliant' : status === 'fail' ? 'Deficient' : status === 'na' ? 'N/A' : 'Not answered'}</span> : <>
              <label className="inspection-choice pass"><input data-pass="true" type="radio" name={`status_${item.id}`} value="pass" defaultChecked={status === 'pass'} required={item.required} /><span>Compliant</span></label>
              <label className="inspection-choice fail"><input type="radio" name={`status_${item.id}`} value="fail" defaultChecked={status === 'fail'} required={item.required} /><span>Deficient</span></label>
              {item.allow_na && <label className="inspection-choice"><input type="radio" name={`status_${item.id}`} value="na" defaultChecked={status === 'na'} required={item.required} /><span>N/A</span></label>}
            </>) : readOnly ? <span className="inspection-read-answer">{response.observed_value || 'Not answered'}</span> : responseType === 'yes_no' ? <>
              <label className="inspection-choice pass"><input type="radio" name={`observed_${item.id}`} value="yes" defaultChecked={response.observed_value === 'yes'} required={item.required}/><span>Yes</span></label>
              <label className="inspection-choice"><input type="radio" name={`observed_${item.id}`} value="no" defaultChecked={response.observed_value === 'no'} required={item.required}/><span>No</span></label>
            </> : <label className="field inspection-inline-answer"><span>Response</span><input name={`observed_${item.id}`} type={responseType === 'number' ? 'number' : responseType === 'date' ? 'date' : 'text'} defaultValue={response.observed_value ?? ''} required={item.required} /></label>}
          </div>
          <div className="inspection-item-detail">
            {responseType === 'compliance' && <label><span>Observed / count</span>{readOnly ? <strong>{response.observed_value || '—'}</strong> : <input name={`observed_${item.id}`} defaultValue={response.observed_value ?? ''} placeholder="Optional" />}</label>}
            <label><span>Notes</span>{readOnly ? <strong>{response.notes || '—'}</strong> : <input name={`notes_${item.id}`} defaultValue={response.notes ?? ''} placeholder={responseType === 'compliance' ? 'Required details if deficient, when applicable' : 'Optional notes'} />}</label>
          </div>
        </div>
      })}
    </div>
  </section>
}
