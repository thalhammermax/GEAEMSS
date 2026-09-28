import type { ReactNode } from 'react'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { Sidebar } from '@/components/sidebar'
import { LogoutButton } from '@/components/logout-button'
import { BrandLogo } from '@/components/brand-logo'

export default async function PortalLayout({ children }: { children: ReactNode }) {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const [{ data: profile }, { data: roles }] = await Promise.all([
    supabase.from('profiles').select('display_name').eq('id', user.id).maybeSingle(),
    supabase.from('user_roles').select('role').eq('user_id', user.id),
  ])

  const roleNames = (roles ?? []).map((r: { role: string }) => r.role)
  const roleLabel = roleNames.includes('system_admin') ? 'System Administrator' : roleNames.includes('agency_admin') ? 'Agency Administrator' : 'Provider'

  return <div className="portal-shell">
    <aside className="sidebar">
      <div className="sidebar-brand"><BrandLogo size="small" /><div><strong>GEAEMS</strong><span>System Portal</span></div></div>
      <Sidebar />
      <div className="sidebar-bottom"><div className="user-card"><div className="user-avatar">{(profile?.display_name || user.email || 'U').slice(0, 1).toUpperCase()}</div><div><strong>{profile?.display_name || user.email}</strong><span>{roleLabel}</span></div></div><LogoutButton /></div>
    </aside>
    <main className="portal-main">{children}</main>
  </div>
}
