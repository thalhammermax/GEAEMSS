'use client'

import { useRouter } from 'next/navigation'
import { createClient } from '@/lib/supabase/client'
import { LogoutIcon } from '@/components/icons'

export function LogoutButton() {
  const router = useRouter()

  async function logout() {
    const supabase = createClient()
    await supabase.auth.signOut()
    router.replace('/login')
    router.refresh()
  }

  return <button className="nav-logout" onClick={logout}><LogoutIcon />Sign out</button>
}
