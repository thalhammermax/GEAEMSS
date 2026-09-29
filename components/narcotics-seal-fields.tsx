'use client'

import { useMemo, useState } from 'react'

type Props = {
  previousSeal?: string | null
  initialSeal?: string | null
  initialReason?: string | null
}

export function NarcoticsSealFields({ previousSeal, initialSeal, initialReason }: Props) {
  const [seal, setSeal] = useState(initialSeal ?? '')
  const previous = (previousSeal ?? '').trim()
  const changed = useMemo(() => Boolean(previous && seal.trim() && seal.trim() !== previous), [previous, seal])

  return <section className="signature-box seal-box">
    <div>
      <span>Security seal</span>
      <h3>Seal verification</h3>
      <p>{previous ? <>Previous submitted seal: <strong>{previous}</strong>. If the current seal number is different, explain why it changed.</> : 'No prior submitted seal is available for this apparatus. Enter the seal number observed during this count.'}</p>
    </div>
    <label className="field">
      <span>Seal Number *</span>
      <input
        name="seal_number"
        value={seal}
        onChange={(event) => setSeal(event.target.value)}
        required
        autoComplete="off"
        placeholder="Enter current seal number"
      />
    </label>
    {changed && <label className="field">
      <span>Reason seal changed *</span>
      <textarea
        name="seal_change_reason"
        rows={3}
        defaultValue={initialReason ?? ''}
        required
        placeholder="Document why the seal was changed or replaced"
      />
    </label>}
    {!changed && <input type="hidden" name="seal_change_reason" value="" />}
  </section>
}
