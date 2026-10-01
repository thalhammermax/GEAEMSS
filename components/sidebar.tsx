'use client'

import Link from 'next/link'
import { usePathname } from 'next/navigation'
import type { ModuleKey } from '@/lib/modules'
import { AmbulanceIcon, ClipboardIcon, CredentialIcon, DashboardIcon, NarcoticsIcon, PeopleIcon, ReportIcon, SettingsIcon } from './icons'

type NavItem = {
  href: string
  label: string
  icon: typeof DashboardIcon
  module?: ModuleKey
}

const ceItem: NavItem = { href: '/ce', label: 'CE Tracking', icon: CredentialIcon, module: 'ce' }

const adminItems: NavItem[] = [
  { href: '/dashboard', label: 'Dashboard', icon: DashboardIcon },
  { href: '/personnel', label: 'Personnel', icon: PeopleIcon, module: 'personnel' },
  { href: '/credentials', label: 'Credentials', icon: CredentialIcon, module: 'credentials' },
  ceItem,
  { href: '/fleet', label: 'Fleet', icon: AmbulanceIcon, module: 'fleet' },
  { href: '/inspections', label: 'Inspections', icon: ClipboardIcon, module: 'inspections' },
  { href: '/narcotics', label: 'Narcotics', icon: NarcoticsIcon, module: 'narcotics' },
  { href: '/reports', label: 'Reports', icon: ReportIcon, module: 'reports' },
  { href: '/administration', label: 'Administration', icon: SettingsIcon },
]

const providerItems: NavItem[] = [
  ceItem,
  { href: '/narcotics', label: 'Narcotics', icon: NarcoticsIcon, module: 'narcotics' },
  { href: '/my-profile', label: 'My Profile', icon: PeopleIcon, module: 'personnel' },
]

const inspectorItems: NavItem[] = [
  { href: '/inspections', label: 'Inspections', icon: ClipboardIcon, module: 'inspections' },
]

const ceRoleItems: NavItem[] = [ceItem]

export function Sidebar({
  providerOnly = false,
  inspectorOnly = false,
  ceOnly = false,
  hasProvider = false,
  enabledModules = [],
}: {
  providerOnly?: boolean
  inspectorOnly?: boolean
  ceOnly?: boolean
  hasProvider?: boolean
  enabledModules?: ModuleKey[]
}) {
  const pathname = usePathname()
  const enabled = new Set(enabledModules)

  const candidates = providerOnly
    ? providerItems
    : inspectorOnly
      ? [...inspectorItems, ...(ceOnly && !hasProvider ? [ceItem] : []), ...(hasProvider ? providerItems : [])]
      : ceOnly
        ? [...ceRoleItems, ...(hasProvider ? providerItems.filter((item) => item.href !== '/ce') : [])]
        : adminItems

  const items = candidates.filter((item) => !item.module || enabled.has(item.module))

  return <nav className="nav-list" aria-label="Primary">
    {items.map(({ href, label, icon: Icon }) => {
      const active = pathname === href || pathname.startsWith(`${href}/`)
      return <Link key={href} href={href} className={`nav-link${active ? ' active' : ''}`}><Icon />{label}</Link>
    })}
  </nav>
}
