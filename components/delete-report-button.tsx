'use client'
import { useState, useTransition } from 'react'
import { useRouter } from 'next/navigation'
import { deleteReportAction } from '@/app/(portal)/reports/actions'

export function DeleteReportButton({ reportId }: { reportId:string }) {
  const router = useRouter(); const [pending,start] = useTransition(); const [error,setError] = useState('')
  return <div>{error && <span className="inline-error">{error}</span>}<button className="danger-button" type="button" disabled={pending} onClick={() => {
    if (!window.confirm('Delete this saved report and its schedule? Historical delivery log entries will also be removed.')) return
    start(async () => { const result = await deleteReportAction(reportId); if (!result.ok) { setError(result.error); return } router.push('/reports'); router.refresh() })
  }}>{pending ? 'Deleting…' : 'Delete report'}</button></div>
}
