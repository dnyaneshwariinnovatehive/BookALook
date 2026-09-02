import Link from 'next/link';
import './globals.css';

export default function LandingPage() {
  return (
    <div className="landing-container">
      <header className="navbar">
        <div className="logo">BookALook</div>
        <nav>
          <Link href="/enquiry" className="btn-primary">Partner With Us</Link>
          <Link href="/login" className="btn-secondary">SuperAdmin Login</Link>
        </nav>
      </header>
      
      <main className="hero">
        <h1>Transform Your Salon Business</h1>
        <p>Join the BookALook marketplace and reach thousands of new customers today.</p>
        <div className="cta-group">
          <Link href="/enquiry" className="btn-large">Get Started Now</Link>
        </div>
      </main>
      
      <section className="features">
        <div className="feature-card">
          <h3>Manage Appointments</h3>
          <p>Real-time availability and smart scheduling.</p>
        </div>
        <div className="feature-card">
          <h3>Grow Revenue</h3>
          <p>Upsell services and handle advance payments seamlessly.</p>
        </div>
        <div className="feature-card">
          <h3>Insights & Analytics</h3>
          <p>Track your growth with powerful reporting tools.</p>
        </div>
      </section>
    </div>
  );
}
