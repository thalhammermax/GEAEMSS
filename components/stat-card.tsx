export function StatCard({ label, value, detail, tone = 'default' }: { label: string; value: string | number; detail?: string; tone?: 'default' | 'warning' | 'danger' | 'success' }) {
  return <article className={`stat-card ${tone}`}><span>{label}</span><strong>{value}</strong>{detail && <small>{detail}</small>}</article>
}
