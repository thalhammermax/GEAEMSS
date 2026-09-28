import type { MetadataRoute } from 'next'

export default function manifest(): MetadataRoute.Manifest {
  return {
    name: 'GEAEMS Portal',
    short_name: 'GEAEMS',
    description: 'Greater Elgin Area EMS System personnel, credential and fleet compliance portal',
    start_url: '/',
    display: 'standalone',
    background_color: '#f4f7f9',
    theme_color: '#0b1f33',
    icons: [
      { src: '/icons/geaems-192.png', sizes: '192x192', type: 'image/png' },
      { src: '/icons/geaems-512.png', sizes: '512x512', type: 'image/png' },
    ],
  }
}
