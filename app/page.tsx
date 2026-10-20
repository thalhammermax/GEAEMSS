import { redirect } from 'next/navigation'
import { getSessionContext } from '@/lib/session'

export default async function Home() {
  const session = await getSessionContext()
  if (!session) redirect('/login')
  redirect(session.isAdmin ? '/dashboard' : session.isSystemInspector ? '/inspections' : '/my-profile')
}
