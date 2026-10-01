import type { Metadata } from 'next'
import Link from 'next/link'
import { PageHeader } from '@/components/page-header'
import { requireSystemAdmin } from '@/lib/admin-auth'
import { getModuleStates, MODULE_CATALOG, moduleLabel } from '@/lib/modules'
import { saveModuleSettings } from './actions'

export const metadata: Metadata = { title: 'Module Rollout' }
type Props = { searchParams: Promise<{ notice?: string; error?: string }> }

export default async function ModulesPage({ searchParams }: Props) {
  const qs = await searchParams
  const { supabase } = await requireSystemAdmin()
  const states = await getModuleStates(supabase)

  return <>
    <PageHeader
      eyebrow="Administration"
      title="Module rollout"
      description="Control which portal modules are live for normal users while you phase the GEAEMS Portal into production."
      action={<Link className="secondary-button button-link" href="/administration">Back to Administration</Link>}
    />

    {qs.notice && <div className="banner success"><div><strong>Modules updated</strong><span>{qs.notice}</span></div></div>}
    {qs.error && <div className="banner danger"><div><strong>Unable to update modules</strong><span>{qs.error}</span></div></div>}

    <div className="banner info"><div><strong>Disabled does not mean deleted.</strong><span>Turning a module off hides it from normal navigation, blocks non-System Administrators from its routes, and pauses module-specific scheduled activity. All existing records remain in place. System Administrators retain maintenance access so a module can be prepared before rollout.</span></div></div>

    <form action={saveModuleSettings} className="form-card">
      <div className="form-card-heading"><div><span>Production rollout</span><h2>Enabled modules</h2></div><span className="pill green">Fleet + Inspections + Reports initially enabled</span></div>
      <div className="role-option-list">
        {MODULE_CATALOG.map((module) => <label key={module.key}>
          <input type="checkbox" name={module.key} defaultChecked={states[module.key]} />
          <span>
            <strong>{module.label}</strong>
            <small>{module.description}{module.dependencies.length ? ` Requires ${module.dependencies.map(moduleLabel).join(' and ')}.` : ''}</small>
          </span>
        </label>)}
      </div>
      <div className="form-actions"><button className="primary-button" type="submit">Save module rollout</button></div>
    </form>

    <section className="panel">
      <div className="panel-heading"><h3>Always available</h3><span>Core portal services</span></div>
      <p className="panel-copy">Dashboard, Administration, agency records, authentication, user access, and module rollout controls remain available because they are required to operate the portal itself.</p>
    </section>
  </>
}
