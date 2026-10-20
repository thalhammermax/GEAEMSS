import type { NextConfig } from 'next'

const nextConfig: NextConfig = {
  poweredByHeader: false,
  // Static assets (logo, icons, manifest) are safe to cache aggressively; the
  // portal pages themselves are always rendered per request.
  async headers() {
    return [
      { source: '/geaems-logo.png', headers: [{ key: 'Cache-Control', value: 'public, max-age=86400, stale-while-revalidate=604800' }] },
      { source: '/icons/:path*', headers: [{ key: 'Cache-Control', value: 'public, max-age=86400, stale-while-revalidate=604800' }] },
    ]
  },
  experimental: {
    // Report builder and inspection forms post large FormData payloads.
    serverActions: { bodySizeLimit: '4mb' },
  },
}

export default nextConfig
