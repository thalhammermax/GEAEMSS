import type { SupabaseClient } from '@supabase/supabase-js'

export type ModuleKey =
  | 'personnel'
  | 'credentials'
  | 'ce'
  | 'fleet'
  | 'inspections'
  | 'narcotics'
  | 'reports'

export type ModuleDefinition = {
  key: ModuleKey
  label: string
  description: string
  defaultEnabled: boolean
  dependencies: ModuleKey[]
}

export const MODULE_CATALOG: ModuleDefinition[] = [
  { key: 'personnel', label: 'Personnel', description: 'Provider records, agency affiliations, provider self-service profile, and personnel administration.', defaultEnabled: false, dependencies: [] },
  { key: 'credentials', label: 'Credentials', description: 'Credential definitions, provider credential records, compliance, submissions, and verification.', defaultEnabled: false, dependencies: ['personnel'] },
  { key: 'ce', label: 'CE Tracking', description: 'CE class scheduling, attendance, transcripts, external certificates, and CE administration.', defaultEnabled: false, dependencies: ['personnel'] },
  { key: 'fleet', label: 'Fleet', description: 'Vehicle master records, vehicle licensing, status, and fleet configuration.', defaultEnabled: true, dependencies: [] },
  { key: 'inspections', label: 'Inspections', description: 'Digital inspection forms, completed inspections, deficiencies, and inspection PDF exports.', defaultEnabled: true, dependencies: ['fleet'] },
  { key: 'narcotics', label: 'Narcotics', description: 'Daily controlled-substance inventory counts, seals, signatures, history, and reporting.', defaultEnabled: false, dependencies: ['fleet'] },
  { key: 'reports', label: 'Reports', description: 'Standard reports, custom multi-module report builder, exports, and scheduled email delivery.', defaultEnabled: true, dependencies: [] },
]

export type ModuleStateMap = Record<ModuleKey, boolean>

export function defaultModuleStates(): ModuleStateMap {
  return Object.fromEntries(MODULE_CATALOG.map((module) => [module.key, module.defaultEnabled])) as ModuleStateMap
}

export async function getModuleStates(supabase: SupabaseClient): Promise<ModuleStateMap> {
  const states = defaultModuleStates()
  const { data, error } = await supabase
    .from('system_module_settings')
    .select('module_key, enabled')

  // During deployment, this keeps the portal usable before migration 019 has
  // been applied. Once the table exists, database settings become authoritative.
  if (error) return states

  for (const row of data ?? []) {
    if (MODULE_CATALOG.some((module) => module.key === row.module_key)) {
      states[row.module_key as ModuleKey] = row.enabled !== false
    }
  }
  return states
}

export function enabledModuleKeys(states: ModuleStateMap) {
  return MODULE_CATALOG.filter((module) => states[module.key]).map((module) => module.key)
}

export function moduleLabel(key?: string | null) {
  return MODULE_CATALOG.find((module) => module.key === key)?.label || key || 'Core'
}

export function moduleForPath(path: string): ModuleKey | null {
  if (path === '/personnel' || path.startsWith('/personnel/')) return 'personnel'
  if (path === '/credentials' || path.startsWith('/credentials/')) return 'credentials'
  if (path === '/my-profile/credentials' || path.startsWith('/my-profile/credentials/')) return 'credentials'
  if (path === '/my-profile' || path.startsWith('/my-profile/')) return 'personnel'
  if (path === '/ce' || path.startsWith('/ce/')) return 'ce'
  if (path === '/fleet' || path.startsWith('/fleet/')) return 'fleet'
  if (path === '/inspections' || path.startsWith('/inspections/')) return 'inspections'
  if (path === '/narcotics' || path.startsWith('/narcotics/')) return 'narcotics'
  if (path === '/reports' || path.startsWith('/reports/')) return 'reports'
  return null
}

export function validateModuleCombination(states: ModuleStateMap) {
  for (const module of MODULE_CATALOG) {
    if (!states[module.key]) continue
    for (const dependency of module.dependencies) {
      if (!states[dependency]) {
        throw new Error(`${module.label} requires ${moduleLabel(dependency)} to be enabled.`)
      }
    }
  }
}
