'use client'

import { useRef, useState } from 'react'

type Props = {
  defaultValue?: string | null
  agencyAddress?: string | null
  readOnly?: boolean
}

export function InspectionLocationField({ defaultValue = '', agencyAddress = '', readOnly = false }: Props) {
  const inputRef = useRef<HTMLInputElement>(null)
  const [useHeadquarters, setUseHeadquarters] = useState(false)
  const autoFilledRef = useRef(false)
  const address = agencyAddress?.trim() ?? ''

  function toggleHeadquarters(checked: boolean) {
    setUseHeadquarters(checked)
    const input = inputRef.current
    if (!input) return

    if (checked) {
      if (!input.value.trim() && address) {
        input.value = address
        autoFilledRef.current = true
      }
      return
    }

    if (autoFilledRef.current && input.value.trim() === address) {
      input.value = ''
    }
    autoFilledRef.current = false
  }

  if (readOnly) {
    return <label className="field"><span>Inspection location</span><input name="inspection_location" defaultValue={defaultValue ?? ''} disabled /></label>
  }

  return <div className="inspection-location-control">
    <label className="field">
      <span>Inspection location</span>
      <input
        ref={inputRef}
        name="inspection_location"
        defaultValue={defaultValue ?? ''}
        onChange={() => { autoFilledRef.current = false }}
      />
    </label>
    <label className="checkbox-row">
      <input
        type="checkbox"
        name="use_agency_headquarters"
        checked={useHeadquarters}
        onChange={(event) => toggleHeadquarters(event.target.checked)}
        disabled={!address}
      />
      <span>Agency Headquarters{address ? ` · ${address}` : ' · No agency address configured'}</span>
    </label>
    <small className="field-help">If Location is entered, that value is used. Otherwise, checking Agency Headquarters uses the agency address.</small>
  </div>
}
