import { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { randomUUID } from 'node:crypto';
import { AddressInfo } from 'node:net';
import { AppModule } from './app.module';
import { AuthService } from './auth.service';
import { configureHttpApp } from './http-config';
import { PrismaService } from './prisma.service';

const postgresDescribe = process.env.RUN_POSTGRES_INTEGRATION === 'true'
  ? describe
  : describe.skip;

postgresDescribe('PostgreSQL-backed project API', () => {
  let app: INestApplication;
  let prisma: PrismaService;
  let auth: AuthService;
  let baseUrl: string;
  const email = `integration-${randomUUID()}@cadpilot.test`;

  beforeAll(async () => {
    const module = await Test.createTestingModule({ imports: [AppModule] })
      .compile();
    app = module.createNestApplication({ bodyParser: false, logger: false });
    configureHttpApp(app);
    await app.listen(0, '127.0.0.1');
    const address = app.getHttpServer().address() as AddressInfo;
    baseUrl = `http://127.0.0.1:${address.port}`;
    prisma = app.get(PrismaService);
    auth = app.get(AuthService);
  });

  afterAll(async () => {
    await prisma.syncMutation.deleteMany({
      where: { project: { owner: { email: { endsWith: '@cadpilot.test' } } } },
    });
    await prisma.projectMember.deleteMany({
      where: { user: { email: { endsWith: '@cadpilot.test' } } },
    });
    await prisma.project.deleteMany({
      where: { owner: { email: { endsWith: '@cadpilot.test' } } },
    });
    await prisma.refreshToken.deleteMany({
      where: { user: { email: { endsWith: '@cadpilot.test' } } },
    });
    await prisma.aiUsage.deleteMany({
      where: { user: { email: { endsWith: '@cadpilot.test' } } },
    });
    await prisma.user.deleteMany({
      where: { email: { endsWith: '@cadpilot.test' } },
    });
    await app.close();
  });

  it('reports ready only while the real PostgreSQL service is reachable', async () => {
    const response = await fetch(`${baseUrl}/v1/health/ready`);

    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toEqual({ status: 'ready' });
  });
  it('rotates and revokes persisted refresh tokens', async () => {
    const issued = await auth.register(
      `refresh-${randomUUID()}@cadpilot.test`,
      'integration-password',
      'Refresh Integration',
    );
    const rotated = await auth.refresh(issued.refreshToken);

    await expect(auth.refresh(issued.refreshToken)).rejects.toThrow(
      'Refresh token is invalid or expired',
    );
    await expect(auth.logout(rotated.refreshToken)).resolves.toEqual({ success: true });
    await expect(auth.refresh(rotated.refreshToken)).rejects.toThrow(
      'Refresh token is invalid or expired',
    );
  });
  it('keeps one persisted user from reading or mutating another user’s project', async () => {
    const ownerEmail = `owner-${randomUUID()}@cadpilot.test`;
    const intruderEmail = `intruder-${randomUUID()}@cadpilot.test`;
    const register = async (email: string) => {
      const response = await fetch(`${baseUrl}/v1/auth/register`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({
          email,
          password: 'integration-password',
          displayName: 'Integration Designer',
        }),
      });
      expect(response.status).toBe(201);
      return response.json() as Promise<{ accessToken: string }>;
    };

    const owner = await register(ownerEmail);
    const intruder = await register(intruderEmail);
    const ownerHeaders = {
      authorization: `Bearer ${owner.accessToken}`,
      'content-type': 'application/json',
    };
    const intruderHeaders = {
      authorization: `Bearer ${intruder.accessToken}`,
      'content-type': 'application/json',
    };
    const create = await fetch(`${baseUrl}/v1/projects`, {
      method: 'POST',
      headers: ownerHeaders,
      body: JSON.stringify({ name: 'Owner-only project' }),
    });
    expect(create.status).toBe(201);
    const project = await create.json() as { id: string };

    const list = await fetch(`${baseUrl}/v1/projects`, { headers: intruderHeaders });
    expect(list.status).toBe(200);
    await expect(list.json()).resolves.toEqual([]);

    const get = await fetch(`${baseUrl}/v1/projects/${project.id}`, { headers: intruderHeaders });
    expect(get.status).toBe(404);

    const sync = await fetch(`${baseUrl}/v1/projects/${project.id}/sync`, {
      method: 'POST',
      headers: intruderHeaders,
      body: JSON.stringify({
        mutationId: randomUUID(),
        baseRevision: 1,
        payload: { name: 'Unauthorized mutation', formatVersion: 1 },
      }),
    });
    expect(sync.status).toBe(404);
  });
  it('persists registration, project creation, and an idempotent sync', async () => {
    const registration = await fetch(`${baseUrl}/v1/auth/register`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        email,
        password: 'integration-password',
        displayName: 'Integration Designer',
      }),
    });
    expect(registration.status).toBe(201);
    const credentials = await registration.json() as { accessToken: string };
    expect(credentials.accessToken).toEqual(expect.any(String));

    const headers = {
      authorization: `Bearer ${credentials.accessToken}`,
      'content-type': 'application/json',
    };
    const create = await fetch(`${baseUrl}/v1/projects`, {
      method: 'POST',
      headers,
      body: JSON.stringify({ name: 'Integration project' }),
    });
    expect(create.status).toBe(201);
    const project = await create.json() as { id: string; revision: number };
    expect(project.revision).toBe(1);

    const mutationId = randomUUID();
    const syncBody = {
      mutationId,
      baseRevision: 1,
      payload: { name: 'Synced integration project', formatVersion: 1 },
    };
    const firstSync = await fetch(`${baseUrl}/v1/projects/${project.id}/sync`, {
      method: 'POST',
      headers,
      body: JSON.stringify(syncBody),
    });
    expect(firstSync.status).toBe(201);
    const applied = await firstSync.json() as { appliedRevision: number };
    expect(applied.appliedRevision).toBe(2);

    const replay = await fetch(`${baseUrl}/v1/projects/${project.id}/sync`, {
      method: 'POST',
      headers,
      body: JSON.stringify(syncBody),
    });
    expect(replay.status).toBe(201);
    await expect(replay.json()).resolves.toEqual(
      expect.objectContaining({ mutationId, appliedRevision: 2 }),
    );

    const list = await fetch(`${baseUrl}/v1/projects`, { headers });
    expect(list.status).toBe(200);
    await expect(list.json()).resolves.toEqual([
      expect.objectContaining({
        id: project.id,
        name: 'Synced integration project',
        revision: 2,
      }),
    ]);
  });
});
