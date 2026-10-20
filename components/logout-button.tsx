import { signOutAction } from '@/app/auth/actions'
import { LogoutIcon } from '@/components/icons'

export function LogoutButton() {
  return <form action={signOutAction} className="logout-form"><button className="nav-logout" type="submit"><LogoutIcon />Sign out</button></form>
}
