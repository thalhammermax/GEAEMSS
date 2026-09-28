'use client'

import { useState } from 'react'

type Props = {
  size?: 'small' | 'medium' | 'large'
  className?: string
}

export function BrandLogo({ size = 'medium', className = '' }: Props) {
  const [failed, setFailed] = useState(false)
  return <div className={`brand-logo ${size} ${className}`.trim()} aria-label="Greater Elgin Area EMS System">
    <span className="brand-logo-fallback" aria-hidden="true">GE</span>
    {!failed && <img src="/geaems-logo.png" alt="Greater Elgin Area EMS System logo" onError={() => setFailed(true)} />}
  </div>
}
