// Streams an instant skeleton while the page's data loads, so navigation feels
// responsive instead of appearing frozen on the previous page.
export default function PortalLoading() {
  return <div className="page-loading" aria-busy="true" aria-live="polite">
    <div className="skeleton title" />
    <div className="skeleton text" />
    <div className="skeleton-grid">
      <div className="skeleton card" /><div className="skeleton card" /><div className="skeleton card" /><div className="skeleton card" />
    </div>
    <div className="skeleton card" style={{ height: 280 }} />
  </div>
}
