import type { Metadata } from 'next'
import { notFound, redirect } from 'next/navigation'
import Link from 'next/link'
import { PageHeader } from '@/components/page-header'
import { createClient } from '@/lib/supabase/server'
import { createAdminClient } from '@/lib/supabase/admin'
import { resendPasswordSetup, saveAgencyAccess, saveUserRoles, setUserActive } from '../actions'

export const metadata: Metadata = { title: 'Manage User' }
type Props = { params: Promise<{ id: string }>; searchParams: Promise<{ error?: string; notice?: string }> }

export default async function ManageUserPage({ params, searchParams }: Props) {
  const { id } = await params
  const { error, notice } = await searchParams
  const supabase = await createClient()
  const { data: { user: currentUser } } = await supabase.auth.getUser()
  if (!currentUser) redirect('/login')
  const { data: systemRole } = await supabase.from('user_roles').select('role').eq('user_id', currentUser.id).eq('role','system_admin').maybeSingle()
  if (!systemRole) redirect('/dashboard')

  let authUser: any = null
  let authError = ''
  try {
    const admin = createAdminClient()
    const result = await admin.auth.admin.getUserById(id)
    if (result.error) throw result.error
    authUser = result.data.user
  } catch (e:any) { authError = e?.message ?? 'Auth user could not be loaded.' }
  if (!authUser && !authError) notFound()

  const [{ data: profile }, { data: roles }, { data: agencies }, { data: access }] = await Promise.all([
    supabase.from('profiles').select('id, provider_id, display_name, active').eq('id', id).maybeSingle(),
    supabase.from('user_roles').select('role').eq('user_id', id),
    supabase.from('agencies').select('id, name, short_name').eq('active', true).order('name'),
    supabase.from('user_agency_access').select('*').eq('user_id', id),
  ])
  const { data: provider } = profile?.provider_id
    ? await supabase.from('providers').select('id, first_name, last_name, preferred_name, email').eq('id', profile.provider_id).maybeSingle()
    : { data: null }
  const roleNames = new Set((roles ?? []).map((r:any) => r.role))
  const accessMap = new Map((access ?? []).map((a:any) => [a.agency_id, a]))

  return <>
    <PageHeader title={profile?.display_name || authUser?.email || 'Portal User'} description={authUser?.email || authError} action={<Link className="secondary-button button-link" href="/administration/users">Back to users</Link>} />
    {notice && <div className="banner success"><div><strong>Success</strong><span>{notice}</span></div></div>}
    {error && <div className="banner danger"><div><strong>User action failed</strong><span>{error}</span></div></div>}
    {authError && <div className="banner danger"><div><strong>Auth administration unavailable</strong><span>{authError}</span></div></div>}

    <div className="profile-grid">
      <section className="form-card compact-card">
        <div className="form-card-heading"><div><span>Account</span><h2>Login identity</h2></div><span className={`pill ${profile?.active !== false ? 'green' : ''}`}>{profile?.active !== false ? 'Active' : 'Disabled'}</span></div>
        <dl className="detail-list"><div><dt>Username</dt><dd>{authUser?.email || 'Unavailable'}</dd></div><div><dt>Email confirmed</dt><dd>{authUser?.email_confirmed_at ? 'Yes' : 'No'}</dd></div><div><dt>Last sign-in</dt><dd>{authUser?.last_sign_in_at ? new Date(authUser.last_sign_in_at).toLocaleString() : 'Never'}</dd></div><div><dt>Created</dt><dd>{authUser?.created_at ? new Date(authUser.created_at).toLocaleString() : 'Unavailable'}</dd></div>{provider && <div><dt>Provider</dt><dd><Link className="text-link" href={`/personnel/${provider.id}`}>{provider.last_name}, {provider.preferred_name || provider.first_name}</Link></dd></div>}</dl>
        <div className="form-actions split-actions"><form action={resendPasswordSetup}><input type="hidden" name="user_id" value={id}/><button className="secondary-button" type="submit" disabled={!authUser?.email}>Send password setup/reset</button></form><form action={setUserActive}><input type="hidden" name="user_id" value={id}/><input type="hidden" name="active" value={profile?.active === false ? 'true' : 'false'}/><button className={`secondary-button ${profile?.active === false ? '' : 'danger-outline'}`} type="submit">{profile?.active === false ? 'Enable account' : 'Disable account'}</button></form></div>
      </section>

      <section className="form-card compact-card">
        <div className="form-card-heading"><div><span>Authorization</span><h2>System roles</h2></div></div>
        <form action={saveUserRoles}><input type="hidden" name="user_id" value={id}/><div className="role-option-list"><label><input type="checkbox" name="roles" value="provider" defaultChecked={roleNames.has('provider')}/><span><strong>Provider</strong><small>Access to the linked provider's own records.</small></span></label><label><input type="checkbox" name="roles" value="agency_admin" defaultChecked={roleNames.has('agency_admin')}/><span><strong>Agency Administrator</strong><small>Agency access is configured below.</small></span></label><label><input type="checkbox" name="roles" value="system_admin" defaultChecked={roleNames.has('system_admin')}/><span><strong>System Administrator</strong><small>Full GEAEMS system administration.</small></span></label></div><div className="form-actions"><button className="primary-button" type="submit">Save roles</button></div></form>
      </section>
    </div>

    <section className="panel"><div className="panel-heading"><h3>Agency administration access</h3><span>Permissions are only used when the user is an Agency Administrator.</span></div><div className="agency-permission-list">{(agencies ?? []).map((agency:any) => { const row:any = accessMap.get(agency.id); return <form action={saveAgencyAccess} className="agency-permission-row" key={agency.id}><input type="hidden" name="user_id" value={id}/><input type="hidden" name="agency_id" value={agency.id}/><label className="agency-access-name"><input type="checkbox" name="enabled" defaultChecked={!!row}/><span><strong>{agency.name}</strong><small>{agency.short_name || ''}</small></span></label><label className="checkbox-row"><input type="checkbox" name="can_manage_personnel" defaultChecked={row?.can_manage_personnel ?? false}/>Personnel</label><label className="checkbox-row"><input type="checkbox" name="can_manage_credentials" defaultChecked={row?.can_manage_credentials ?? true}/>Credentials</label><label className="checkbox-row"><input type="checkbox" name="can_manage_fleet" defaultChecked={row?.can_manage_fleet ?? false}/>Fleet</label><button className="secondary-button small" type="submit">Save</button></form>})}</div></section>
  </>
}
