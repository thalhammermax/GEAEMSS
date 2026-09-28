import type { ReactNode } from 'react'

export function PageHeader({ eyebrow = 'GEAEMS System', title, description, action }: { eyebrow?: string; title: string; description?: string; action?: ReactNode }) {
  return <header className="page-header"><div><p className="eyebrow">{eyebrow}</p><h1>{title}</h1>{description && <p className="page-description">{description}</p>}</div>{action && <div>{action}</div>}</header>
}
