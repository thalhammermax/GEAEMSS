import type { ReactNode } from 'react'
import { redirect } from 'next/navigation'
import { Sidebar } from '@/components/sidebar'
import { LogoutButton } from '@/components/logout-button'
import { BrandLogo } from '@/components/brand-logo'
import { enabledModuleKeys } from '@/lib/modules'
import { requireSession } from '@/lib/session'

export default async function PortalLayout({ children }: { children: ReactNode }) {
  // Single cached lookup shared with the proxy and every page in this request.
  const session = await requireSession()
  const { isSystemAdmin, isAgencyAdmin, isSystemInspector, isCECoordinator, isCEInstructor, isAdmin, hasProvider } = session

  const inspectorOnly = isSystemInspector && !isAdmin
  const ceOnly = (isCECoordinator || isCEInstructor) && !isAdmin
  const providerOnly = !isAdmin && !isSystemInspector && !isCECoordinator && !isCEInstructor

  if (providerOnly && !hasProvider) redirect('/auth/disabled')

  const roleLabel = isSystemAdmin ? 'System Administrator'
    : isAgencyAdmin ? 'Agency Administrator'
    : isCECoordinator ? 'CE Coordinator'
    : isCEInstructor ? 'CE Instructor'
    : isSystemInspector ? 'System Inspector'
    : 'Provider'

  const name = session.displayName || session.user.email || 'U'

  return <div className="portal-shell">
    <aside className="sidebar">
      <div className="sidebar-brand"><BrandLogo size="small" /><div><strong>GEAEMS</strong><span>System Portal</span></div></div>
      <Sidebar providerOnly={providerOnly} inspectorOnly={inspectorOnly} ceOnly={ceOnly} hasProvider={hasProvider} enabledModules={enabledModuleKeys(session.modules)} />
      <div className="sidebar-bottom"><div className="user-card"><div className="user-avatar">{name.slice(0, 1).toUpperCase()}</div><div><strong>{name}</strong><span>{roleLabel}</span></div></div><LogoutButton /></div>
    </aside>
    <main className="portal-main">{children}</main>
  </div>
}
