'use client'

import Link from 'next/link'
import { usePathname } from 'next/navigation'
import { AmbulanceIcon, ClipboardIcon, CredentialIcon, DashboardIcon, PeopleIcon, ReportIcon, SettingsIcon } from './icons'

const adminItems = [
  { href: '/dashboard', label: 'Dashboard', icon: DashboardIcon },
  { href: '/personnel', label: 'Personnel', icon: PeopleIcon },
  { href: '/credentials', label: 'Credentials', icon: CredentialIcon },
  { href: '/fleet', label: 'Fleet', icon: AmbulanceIcon },
  { href: '/inspections', label: 'Inspections', icon: ClipboardIcon },
  { href: '/reports', label: 'Reports', icon: ReportIcon },
  { href: '/administration', label: 'Administration', icon: SettingsIcon },
]

const providerItems = [
  { href: '/my-profile', label: 'My Profile', icon: PeopleIcon },
]

export function Sidebar({ providerOnly = false }: { providerOnly?: boolean }) {
  const pathname = usePathname()
  const items = providerOnly ? providerItems : adminItems
  return <nav className="nav-list" aria-label="Primary">
    {items.map(({ href, label, icon: Icon }) => {
      const active = pathname === href || pathname.startsWith(`${href}/`)
      return <Link key={href} href={href} className={`nav-link${active ? ' active' : ''}`}><Icon />{label}</Link>
    })}
  </nav>
}
