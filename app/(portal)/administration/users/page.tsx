import type { Metadata } from 'next'
import Link from 'next/link'
import { redirect } from 'next/navigation'
import { PageHeader } from '@/components/page-header'
import { createClient } from '@/lib/supabase/server'
import { createAdminClient } from '@/lib/supabase/admin'
import { inviteProviderUser } from './actions'

export const metadata: Metadata = { title: 'User Management' }
type Props = { searchParams: Promise<{ error?: string; notice?: string }> }

export default async function UsersPage({ searchParams }: Props) {
  const { error, notice } = await searchParams
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')
  const { data: systemRole } = await supabase.from('user_roles').select('role').eq('user_id', user.id).eq('role','system_admin').maybeSingle()
  if (!systemRole) redirect('/dashboard')

  let authUsers: any[] = []
  let configError = ''
  try {
    const admin = createAdminClient()
    const { data, error: listError } = await admin.auth.admin.listUsers({ page: 1, perPage: 1000 })
    if (listError) throw listError
    authUsers = data.users
  } catch (e: any) {
    configError = e?.message ?? 'Auth users could not be loaded.'
  }

  const [{ data: profiles }, { data: roles }, { data: providers }] = await Promise.all([
    supabase.from('profiles').select('id, provider_id, display_name, active'),
    supabase.from('user_roles').select('user_id, role'),
    supabase.from('providers').select('id, first_name, last_name, preferred_name, email').order('last_name').order('first_name'),
  ])
  const profileMap = new Map((profiles ?? []).map((p: any) => [p.id, p]))
  const roleMap = new Map<string,string[]>()
  for (const r of roles ?? []) roleMap.set(r.user_id, [...(roleMap.get(r.user_id) ?? []), r.role])
  const linkedProviderIds = new Set((profiles ?? []).map((p: any) => p.provider_id).filter(Boolean))
  const eligibleProviders = (providers ?? []).filter((p: any) => p.email && !linkedProviderIds.has(p.id))

  return <>
    <PageHeader title="User Management" description="Manage portal accounts, roles, account status and provider invitations. Provider email addresses are used as login usernames." />
    {notice && <div className="banner success"><div><strong>Success</strong><span>{notice}</span></div></div>}
    {error && <div className="banner danger"><div><strong>User action failed</strong><span>{error}</span></div></div>}
    {configError && <div className="banner danger"><div><strong>Server-side Auth administration is not configured</strong><span>{configError}</span></div></div>}

    <div className="summary-strip"><div><span>Portal accounts</span><strong>{authUsers.length}</strong></div><div><span>Providers without login</span><strong>{eligibleProviders.length}</strong></div><div><span>Active profiles</span><strong>{(profiles ?? []).filter((p:any) => p.active).length}</strong></div></div>

    <section className="form-card compact-card">
      <div className="form-card-heading"><div><span>Provider account</span><h2>Send account setup invitation</h2></div></div>
      <p className="panel-copy">This is optional. A provider can exist in the system without a portal account. Selecting a provider sends an email to the address on their personnel record and links the resulting login to that provider.</p>
      <form action={inviteProviderUser} className="form-grid three">
        <label className="field span-two"><span>Provider</span><select name="provider_id" required defaultValue=""><option value="" disabled>Select a provider with an email address</option>{eligibleProviders.map((p:any) => <option key={p.id} value={p.id}>{p.last_name}, {p.preferred_name || p.first_name} — {p.email}</option>)}</select></label>
        <div className="field field-button"><span>&nbsp;</span><button className="primary-button" type="submit" disabled={!!configError}>Send setup email</button></div>
      </form>
    </section>

    <div className="table-card">{authUsers.length === 0 ? <div className="empty-state"><strong>No Auth users available</strong><span>{configError || 'No portal accounts have been created yet.'}</span></div> : <table><thead><tr><th>User</th><th>Linked provider</th><th>Roles</th><th>Last sign-in</th><th>Status</th><th></th></tr></thead><tbody>{authUsers.map((u:any) => { const profile:any = profileMap.get(u.id); const provider:any = (providers ?? []).find((p:any) => p.id === profile?.provider_id); const userRoles = roleMap.get(u.id) ?? []; return <tr key={u.id}><td><strong>{profile?.display_name || u.email || 'User'}</strong><div className="muted-code">{u.email}</div></td><td>{provider ? <Link href={`/personnel/${provider.id}`}>{provider.last_name}, {provider.preferred_name || provider.first_name}</Link> : <span className="muted-code">Not linked</span>}</td><td>{userRoles.length ? userRoles.map((r) => r.replace('_',' ')).join(', ') : 'No role'}</td><td>{u.last_sign_in_at ? new Date(u.last_sign_in_at).toLocaleString() : 'Never'}</td><td><span className={`pill ${profile?.active === true ? 'green' : ''}`}>{!profile ? 'Unprovisioned' : profile.active ? 'Active' : 'Disabled'}</span></td><td className="table-action"><Link href={`/administration/users/${u.id}`}>Manage</Link></td></tr> })}</tbody></table>}</div>
  </>
}
