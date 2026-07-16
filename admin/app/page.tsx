'use client';

import { FormEvent, useMemo, useState } from 'react';

type Overview = { users: number; activeProjects: number; archivedProjects: number; mutations: number; aiRequests: number; aiTokens: number };
type AdminUser = { id: string; email: string; displayName: string; createdAt: string; _count: { projects: number; refreshTokens: number } };
type AdminProject = { id: string; name: string; status: string; revision: number; updatedAt: string; owner: { email: string; displayName: string } };
type Audit = { aiUsage: { id: string; provider: string; model: string; totalTokens: number; createdAt: string; user: { email: string; displayName: string } }[]; mutations: { id: string; status: string; baseRevision: number; appliedRevision: number | null; createdAt: string; project: { name: string } }[] };
type DashboardData = { overview: Overview; users: AdminUser[]; projects: AdminProject[]; audit: Audit };
type ProviderKey = { id: string; provider: 'GEMINI'|'GROQ'|'OPENROUTER'|'OPENAI'; label: string; keyHint: string; enabled: boolean; priority: number };

const apiUrl = process.env.NEXT_PUBLIC_CADPILOT_API_URL ?? 'http://localhost:3000/v1';

class AdminRequestError extends Error {
  constructor(readonly status: number, message: string) { super(message); }
}

async function request<T>(path: string, token: string): Promise<T> {
  const response = await fetch(`${apiUrl}${path}`, { headers: { authorization: `Bearer ${token}` } });
  if (!response.ok) {
    const message = response.status === 401 ? 'Your session expired. Sign in again.' : response.status === 403 ? 'This account is not in CADPILOT_SUPER_ADMIN_EMAILS.' : 'Could not load admin data. Try again.';
    throw new AdminRequestError(response.status, message);
  }
  return response.json() as Promise<T>;
}
async function write<T>(path: string, token: string, method: string, body?: unknown): Promise<T> { const response = await fetch(`${apiUrl}${path}`, { method, headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' }, body: body ? JSON.stringify(body) : undefined }); if (!response.ok) throw new AdminRequestError(response.status, 'Could not update AI provider keys.'); return response.json() as Promise<T>; }

async function loadDashboard(token: string): Promise<DashboardData> {
  const [overview, users, projects, audit] = await Promise.all([
    request<Overview>('/admin/overview', token), request<AdminUser[]>('/admin/users', token),
    request<AdminProject[]>('/admin/projects', token), request<Audit>('/admin/audit', token),
  ]);
  return { overview, users, projects, audit };
}

export default function AdminPage() {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [token, setToken] = useState<string | null>(null);
  const [overview, setOverview] = useState<Overview | null>(null);
  const [users, setUsers] = useState<AdminUser[]>([]);
  const [projects, setProjects] = useState<AdminProject[]>([]);
  const [audit, setAudit] = useState<Audit>({ aiUsage: [], mutations: [] });
  const [query, setQuery] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [providerKeys, setProviderKeys] = useState<ProviderKey[]>([]);
  const [provider, setProvider] = useState<ProviderKey['provider']>('GROQ'); const [keys, setKeys] = useState(''); const [keyLabel, setKeyLabel] = useState('');

  function signOut() { setToken(null); setOverview(null); setUsers([]); setProjects([]); setAudit({ aiUsage: [], mutations: [] }); setQuery(''); setPassword(''); }
  function applyDashboard(data: DashboardData) { setOverview(data.overview); setUsers(data.users); setProjects(data.projects); setAudit(data.audit); }
  function handleRequestError(reason: unknown) { const message = reason instanceof Error ? reason.message : 'Could not open the dashboard.'; if (reason instanceof AdminRequestError && reason.status === 401) signOut(); setError(message); }

  async function signIn(event: FormEvent) {
    event.preventDefault(); setLoading(true); setError(null);
    try {
      const response = await fetch(`${apiUrl}/auth/login`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ email, password }) });
      if (!response.ok) throw new Error('Sign-in failed.');
      const body = await response.json() as { accessToken?: string };
      if (!body.accessToken) throw new Error('Invalid sign-in response.');
      applyDashboard(await loadDashboard(body.accessToken)); setProviderKeys(await request<ProviderKey[]>('/admin/ai/providers', body.accessToken)); setToken(body.accessToken); setPassword('');
    } catch (reason) { handleRequestError(reason); } finally { setLoading(false); }
  }
  async function refreshDashboard() {
    if (!token) return;
    setLoading(true); setError(null);
    try { applyDashboard(await loadDashboard(token)); } catch (reason) { handleRequestError(reason); } finally { setLoading(false); }
  }
  async function saveProviderKeys(event: FormEvent) { event.preventDefault(); if (!token) return; setLoading(true); setError(null); try { setProviderKeys(await write<ProviderKey[]>('/admin/ai/providers', token, 'POST', { provider, keys, label: keyLabel, priority: 0 })); setKeys(''); setKeyLabel(''); } catch (reason) { handleRequestError(reason); } finally { setLoading(false); } }

  const normalizedQuery = query.trim().toLowerCase();
  const visibleUsers = useMemo(() => users.filter((user) => !normalizedQuery || `${user.displayName} ${user.email}`.toLowerCase().includes(normalizedQuery)), [users, normalizedQuery]);
  const visibleProjects = useMemo(() => projects.filter((project) => !normalizedQuery || `${project.name} ${project.owner.email} ${project.status}`.toLowerCase().includes(normalizedQuery)), [projects, normalizedQuery]);
  if (!token) return <main className="login"><section><p className="eyebrow">CADPILOT / ADMIN</p><h1>Admin operations</h1><p className="muted">Secure operations access for authorized CadPilot administrators.</p><form onSubmit={signIn}><label>Email<input type="email" required value={email} onChange={(event) => setEmail(event.target.value)} /></label><label>Password<input type="password" required minLength={8} value={password} onChange={(event) => setPassword(event.target.value)} /></label>{error && <p className="error" role="alert">{error}</p>}<button disabled={loading}>{loading ? 'Checking access...' : 'Open dashboard'}</button></form><p className="hint">Your session is held only in this browser and is cleared when you sign out or refresh.</p></section></main>;

  const cards = [['Users', overview?.users], ['Active projects', overview?.activeProjects], ['Archived', overview?.archivedProjects], ['AI requests', overview?.aiRequests], ['AI tokens', overview?.aiTokens], ['Sync mutations', overview?.mutations]];
  return <main className="dashboard">
    <header><div><p className="eyebrow">CADPILOT / SUPER ADMIN</p><h1>Operations overview</h1></div><div className="headerActions"><button className="secondary" onClick={refreshDashboard} disabled={loading}>{loading ? 'Refreshing...' : 'Refresh data'}</button><button className="secondary" onClick={signOut}>Sign out</button></div></header>
    {error && <p className="error notice" role="alert">{error}</p>}
    <section className="cards">{cards.map(([label, value]) => <article key={String(label)}><span>{label}</span><strong>{Number(value ?? 0).toLocaleString()}</strong></article>)}</section>
    <section className="panel"><div className="panelTitle"><h2>AI providers &amp; keys</h2><span>Encrypted and write-only</span></div><div className="providerPanel"><form onSubmit={saveProviderKeys}><label>Provider<select value={provider} onChange={(event) => setProvider(event.target.value as ProviderKey['provider'])}><option>GEMINI</option><option>GROQ</option><option>OPENROUTER</option><option>OPENAI</option></select></label><label>Label<input value={keyLabel} onChange={(event) => setKeyLabel(event.target.value)} placeholder="Production keys" /></label><label>API key(s), comma-separated<textarea required value={keys} onChange={(event) => setKeys(event.target.value)} placeholder="key_1, key_2" /></label><button disabled={loading}>Save encrypted keys</button></form><div>{providerKeys.length === 0 ? <p className="muted">No provider keys configured.</p> : providerKeys.map((key) => <p key={key.id}><b>{key.provider}</b> · {key.label} · {key.keyHint} · {key.enabled ? 'enabled' : 'disabled'}</p>)}</div></div></section>
    <section className="listControls"><label>Filter users and projects<input value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Name, email, project, or status" /></label><span>{visibleUsers.length} users / {visibleProjects.length} projects shown</span></section>
    <section className="grid">
      <article className="panel"><div className="panelTitle"><h2>Recent users</h2><span>Read-only</span></div><table><thead><tr><th>User</th><th>Projects</th><th>Created</th></tr></thead><tbody>{visibleUsers.length === 0 ? <tr><td colSpan={3}>No users match this filter.</td></tr> : visibleUsers.map((user) => <tr key={user.id}><td><b>{user.displayName}</b><small>{user.email}</small></td><td>{user._count.projects}</td><td>{new Date(user.createdAt).toLocaleDateString()}</td></tr>)}</tbody></table></article>
      <article className="panel"><div className="panelTitle"><h2>Recent projects</h2><span>Read-only</span></div><table><thead><tr><th>Project</th><th>Revision</th><th>Status</th></tr></thead><tbody>{visibleProjects.length === 0 ? <tr><td colSpan={3}>No projects match this filter.</td></tr> : visibleProjects.map((project) => <tr key={project.id}><td><b>{project.name}</b><small>{project.owner.email}</small></td><td>{project.revision}</td><td><em>{project.status}</em></td></tr>)}</tbody></table></article>
      <article className="panel audit"><div className="panelTitle"><h2>Recent AI usage</h2><span>Metadata only</span></div><table><thead><tr><th>User</th><th>Model</th><th>Tokens</th></tr></thead><tbody>{audit.aiUsage.length === 0 ? <tr><td colSpan={3}>No AI usage recorded yet.</td></tr> : audit.aiUsage.slice(0, 10).map((usage) => <tr key={usage.id}><td><b>{usage.user.displayName}</b><small>{usage.user.email}</small></td><td>{usage.model}</td><td>{usage.totalTokens.toLocaleString()}</td></tr>)}</tbody></table></article>
      <article className="panel audit"><div className="panelTitle"><h2>Recent sync activity</h2><span>Metadata only</span></div><table><thead><tr><th>Project</th><th>Revision</th><th>Status</th></tr></thead><tbody>{audit.mutations.length === 0 ? <tr><td colSpan={3}>No sync activity recorded yet.</td></tr> : audit.mutations.slice(0, 10).map((mutation) => <tr key={mutation.id}><td>{mutation.project.name}</td><td>{mutation.baseRevision} to {mutation.appliedRevision ?? 'pending'}</td><td><em>{mutation.status}</em></td></tr>)}</tbody></table></article>
    </section>
  </main>;
}
