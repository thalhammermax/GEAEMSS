'use client'

import Link from 'next/link'
import { usePathname } from 'next/navigation'
import { AmbulanceIcon, ClipboardIcon, CredentialIcon, DashboardIcon, NarcoticsIcon, PeopleIcon, ReportIcon, SettingsIcon } from './icons'

const ceItem = { href: '/ce', label: 'CE Tracking', icon: CredentialIcon }

const adminItems = [
  { href: '/dashboard', label: 'Dashboard', icon: DashboardIcon },
  { href: '/personnel', label: 'Personnel', icon: PeopleIcon },
  { href: '/credentials', label: 'Credentials', icon: CredentialIcon },
  ceItem,
  { href: '/fleet', label: 'Fleet', icon: AmbulanceIcon },
  { href: '/inspections', label: 'Inspections', icon: ClipboardIcon },
  { href: '/narcotics', label: 'Narcotics', icon: NarcoticsIcon },
  { href: '/reports', label: 'Reports', icon: ReportIcon },
  { href: '/administration', label: 'Administration', icon: SettingsIcon },
]

const providerItems = [
  ceItem,
  { href: '/narcotics', label: 'Narcotics', icon: NarcoticsIcon },
  { href: '/my-profile', label: 'My Profile', icon: PeopleIcon },
]

const inspectorItems = [
  { href: '/inspections', label: 'Inspections', icon: ClipboardIcon },
]

const ceRoleItems = [ceItem]

export function Sidebar({ providerOnly = false, inspectorOnly = false, ceOnly = false, hasProvider = false }: { providerOnly?: boolean; inspectorOnly?: boolean; ceOnly?: boolean; hasProvider?: boolean }) {
  const pathname = usePathname()
  const items = providerOnly
    ? providerItems
    : inspectorOnly
      ? [...inspectorItems, ...(ceOnly && !hasProvider ? [ceItem] : []), ...(hasProvider ? providerItems : [])]
      : ceOnly
        ? [...ceRoleItems, ...(hasProvider ? providerItems.filter((item) => item.href !== '/ce') : [])]
        : adminItems
  return <nav className="nav-list" aria-label="Primary">
    {items.map(({ href, label, icon: Icon }) => {
      const active = pathname === href || pathname.startsWith(`${href}/`)
      return <Link key={href} href={href} className={`nav-link${active ? ' active' : ''}`}><Icon />{label}</Link>
    })}
  </nav>
}
