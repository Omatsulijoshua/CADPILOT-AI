'use client';

import { FormEvent, useState } from 'react';

type Overview = { users: number; activeProjects: number; archivedProjects: number; mutations: number; aiRequests: number; aiTokens: number };
type AdminUser = { id: string; email: string; displayName: string; createdAt: string; _count: { projects: number; refreshTokens: number } };
type AdminProject = { id: string; name: string; status: string; revision: number; updatedAt: string; owner: { email: string; displayName: string } };

const apiUrl = process.env.NEXT_PUBLIC_CADPILOT_API_URL ?? 'http://localhost:3000/v1';

async function request<T>(path: string, token: string): Promise<T> {
  const response = await fetch(`${apiUrl}${path}`, { headers: { authorization: `Bearer ${token}` } });
  if (!response.ok) throw new Error(response.status === 403 ? 'This account is not in CADPILOT_SUPER_ADMIN_EMAILS.' : 'Could not load admin data.');
  return response.json() as Promise<T>;
}

export default function AdminPage() {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [token, setToken] = useState<string | null>(null);
  const [overview, setOverview] = useState<Overview | null>(null);
  const [users, setUsers] = useState<AdminUser[]>([]);
  const [projects, setProjects] = useState<AdminProject[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  async function signIn(event: FormEvent) {
    event.preventDefault();
    setLoading(true); setError(null);
    try {
      const response = await fetch(`${apiUrl}/auth/login`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ email, password }) });
      if (!response.ok) throw new Error('Sign-in failed.');
      const body = await response.json() as { accessToken?: string };
      if (!body.accessToken) throw new Error('Invalid sign-in response.');
      const accessToken = body.accessToken;
      const [nextOverview, nextUsers, nextProjects] = await Promise.all([
        request<Overview>('/admin/overview', accessToken), request<AdminUser[]>('/admin/users', accessToken), request<AdminProject[]>('/admin/projects', accessToken),
      ]);
      setToken(accessToken); setOverview(nextOverview); setUsers(nextUsers); setProjects(nextProjects); setPassword('');
    } catch (reason) { setError(reason instanceof Error ? reason.message : 'Could not open the dashboard.'); }
    finally { setLoading(false); }
  }

  if (!token) return <main className="login"><section><p className="eyebrow">CADPILOT / PHASE 8</p><h1>Admin operations</h1><p className="muted">Read-only operational data. Access is enforced by the CadPilot API allowlist.</p><form onSubmit={signIn}><label>Email<input type="email" required value={email} onChange={(event) => setEmail(event.target.value)} /></label><label>Password<input type="password" required minLength={8} value={password} onChange={(event) => setPassword(event.target.value)} /></label>{error && <p className="error">{error}</p>}<button disabled={loading}>{loading ? 'Checking access…' : 'Open dashboard'}</button></form><p className="hint">Set <code>CADPILOT_SUPER_ADMIN_EMAILS</code> on the API. The access token is held only in this browser memory and is cleared on refresh.</p></section></main>;

  const cards = [['Users', overview?.users], ['Active projects', overview?.activeProjects], ['Archived', overview?.archivedProjects], ['AI requests', overview?.aiRequests], ['AI tokens', overview?.aiTokens], ['Sync mutations', overview?.mutations]];
  return <main className="dashboard"><header><div><p className="eyebrow">CADPILOT / SUPER ADMIN</p><h1>Operations overview</h1></div><button className="secondary" onClick={() => { setToken(null); setOverview(null); setUsers([]); setProjects([]); }}>Sign out</button></header><section className="cards">{cards.map(([label, value]) => <article key={String(label)}><span>{label}</span><strong>{Number(value ?? 0).toLocaleString()}</strong></article>)}</section><section className="grid"><article className="panel"><div className="panelTitle"><h2>Recent users</h2><span>Read-only</span></div><table><thead><tr><th>User</th><th>Projects</th><th>Created</th></tr></thead><tbody>{users.map((user) => <tr key={user.id}><td><b>{user.displayName}</b><small>{user.email}</small></td><td>{user._count.projects}</td><td>{new Date(user.createdAt).toLocaleDateString()}</td></tr>)}</tbody></table></article><article className="panel"><div className="panelTitle"><h2>Recent projects</h2><span>Read-only</span></div><table><thead><tr><th>Project</th><th>Revision</th><th>Status</th></tr></thead><tbody>{projects.map((project) => <tr key={project.id}><td><b>{project.name}</b><small>{project.owner.email}</small></td><td>{project.revision}</td><td><em>{project.status}</em></td></tr>)}</tbody></table></article></section></main>;
}
