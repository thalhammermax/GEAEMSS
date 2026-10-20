import { BrandLogo } from '@/components/brand-logo'
import { signOutAction } from '@/app/auth/actions'

export default function DisabledPage() {
  return <main className="login-page"><section className="login-panel"><BrandLogo size="large"/><div className="login-heading"><p className="eyebrow">Greater Elgin Area EMS System</p><h1>Portal access unavailable</h1><p>Your GEAEMS Portal account is disabled or has not been provisioned. Contact System Administration if you believe you should have access.</p></div><form action={signOutAction}><button className="primary-button" type="submit">Return to sign in</button></form></section><aside className="login-art" aria-hidden="true"><div className="cross"><span/><span/></div></aside></main>
}
