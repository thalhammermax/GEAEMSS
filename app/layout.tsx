import type { ReactNode } from 'react'
import type { Metadata } from 'next'
import './globals.css'

export const metadata: Metadata = {
  title: { default: 'GEAEMS Portal', template: '%s | GEAEMS Portal' },
  description: 'Greater Elgin Area EMS System personnel and fleet compliance portal',
  manifest: '/manifest.webmanifest',
}

export default function RootLayout({ children }: Readonly<{ children: ReactNode }>) {
  return <html lang="en"><body>{children}</body></html>
}
