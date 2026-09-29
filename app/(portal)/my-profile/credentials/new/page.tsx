import type { Metadata } from 'next'
import Link from 'next/link'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { PageHeader } from '@/components/page-header'
import { CredentialSubmissionForm, type CredentialSubmissionType } from '@/components/credential-submission-form'

export const metadata: Metadata = { title: 'Add Credential' }
type Props = { searchParams: Promise<{ type?: string }> }

export default async function AddCredentialPage({ searchParams }: Props) {
  const { type: requestedType } = await searchParams
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const { data: profile } = await supabase.from('profiles').select('provider_id').eq('id', user.id).maybeSingle()
  if (!profile?.provider_id) redirect('/auth/disabled')
  const providerId = profile.provider_id

  const [{ data: types }, { data: openSubmissions }, { data: currentCredentials }] = await Promise.all([
    supabase.from('credential_types').select('id, name, category, scope_type, agency_id, requires_number, requires_issue_date, requires_expiration_date, requires_document, requires_verification, agencies(name, short_name)').eq('active', true).order('scope_type').order('name'),
    supabase.from('credential_submissions').select('id, credential_type_id, status').eq('provider_id', providerId).in('status', ['draft', 'pending', 'changes_requested']),
    supabase.from('provider_credentials').select('credential_type_id, credential_number, issue_date, expiration_date').eq('provider_id', providerId).eq('is_current', true).eq('verification_status', 'verified'),
  ])

  const rows = (types ?? []) as any[]
  const credentialTypes: CredentialSubmissionType[] = rows.map((row:any) => ({
    id: row.id,
    name: row.name,
    category: row.category,
    scope_type: row.scope_type,
    agency_id: row.agency_id,
    agency_name: row.scope_type === 'agency' ? (row.agencies?.short_name || row.agencies?.name || 'Agency') : null,
    requires_number: !!row.requires_number,
    requires_issue_date: !!row.requires_issue_date,
    requires_expiration_date: !!row.requires_expiration_date,
    requires_document: !!row.requires_document,
    requires_verification: !!row.requires_verification,
  }))

  const open = (openSubmissions ?? []) as any[]
  if (requestedType) {
    const existing = open.find((row) => row.credential_type_id === requestedType)
    if (existing) redirect(`/my-profile/credentials/submissions/${existing.id}`)
  }

  const openTypeIds = new Set(open.map((row) => row.credential_type_id))
  const availableTypes = credentialTypes.filter((row) => !openTypeIds.has(row.id))
  const allowedRequestedType = requestedType && availableTypes.some((row) => row.id === requestedType) ? requestedType : null
  const currentMap: Record<string, any> = {}
  for (const row of (currentCredentials ?? []) as any[]) currentMap[row.credential_type_id] = row

  return <>
    <PageHeader eyebrow="My Credentials" title="Add or renew credential" description="Submit a credential for your GEAEMS System provider record." action={<Link className="secondary-button button-link" href="/my-profile">Back to My Profile</Link>} />
    <CredentialSubmissionForm providerId={providerId} credentialTypes={availableTypes} preselectedTypeId={allowedRequestedType} currentCredentials={currentMap} />
  </>
}
