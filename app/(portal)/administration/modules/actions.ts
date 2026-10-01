'use server'

import { revalidatePath } from 'next/cache'
import { redirect } from 'next/navigation'
import { requireSystemAdmin } from '@/lib/admin-auth'
import { MODULE_CATALOG, defaultModuleStates, validateModuleCombination } from '@/lib/modules'

function checked(formData: FormData, key: string) {
  return formData.get(key) === 'on'
}

export async function saveModuleSettings(formData: FormData) {
  try {
    const { supabase, user } = await requireSystemAdmin()
    const states = defaultModuleStates()

    for (const module of MODULE_CATALOG) {
      states[module.key] = checked(formData, module.key)
    }
    validateModuleCombination(states)

    const { error } = await supabase
      .from('system_module_settings')
      .upsert(
        MODULE_CATALOG.map((module) => ({
          module_key: module.key,
          enabled: states[module.key],
          updated_by: user.id,
          updated_at: new Date().toISOString(),
        })),
        { onConflict: 'module_key' }
      )

    if (error) throw error
  } catch (error: any) {
    redirect(`/administration/modules?error=${encodeURIComponent(error?.message || 'Module settings could not be saved.')}`)
  }

  revalidatePath('/', 'layout')
  revalidatePath('/dashboard')
  revalidatePath('/administration')
  revalidatePath('/administration/modules')
  revalidatePath('/reports')
  redirect(`/administration/modules?notice=${encodeURIComponent('Module rollout settings saved.')}`)
}
