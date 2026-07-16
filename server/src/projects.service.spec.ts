import { BadRequestException, ConflictException, NotFoundException } from '@nestjs/common';
import { ProjectsService } from './projects.service';

function createPrisma() {
  const transactionClient = {
    project: {
      create: jest.fn(),
      update: jest.fn(),
    },
    syncMutation: {
      create: jest.fn(),
    },
  };
  return {
    transactionClient,
    prisma: {
      project: {
        findMany: jest.fn(),
        findFirst: jest.fn(),
        create: jest.fn(),
        findUnique: jest.fn(),
        updateMany: jest.fn(),
      },
      projectMember: {
        findMany: jest.fn(),
        upsert: jest.fn(),
      },
      user: {
        findUnique: jest.fn(),
      },
      syncMutation: {
        findUnique: jest.fn(),
        findMany: jest.fn(),
        updateMany: jest.fn(),
      },
      $transaction: jest.fn(
        (operation: (tx: typeof transactionClient) => unknown) =>
          operation(transactionClient),
      ),
    },
  };
}

describe('ProjectsService create', () => {
  test('trims project names before persisting them', async () => {
    const { prisma } = createPrisma();
    prisma.project.create.mockResolvedValue({ id: 'project-1' });
    const service = new ProjectsService(prisma as never);

    await service.create('owner-1', '  Kitchen cabinet  ');

    expect(prisma.project.create).toHaveBeenCalledWith({
      data: expect.objectContaining({
        ownerId: 'owner-1',
        name: 'Kitchen cabinet',
      }),
    });
  });
});
describe('ProjectsService sync', () => {
  test('first sync atomically creates the owned project at remote revision one', async () => {
    const { prisma, transactionClient } = createPrisma();
    prisma.syncMutation.findUnique.mockResolvedValue(null);
    prisma.project.findUnique.mockResolvedValue(null);
    transactionClient.project.create.mockResolvedValue({ revision: 1 });
    transactionClient.syncMutation.create.mockImplementation(
      async ({ data }: { data: object }) => data,
    );
    const service = new ProjectsService(prisma as never);

    const result = await service.sync(
      'owner-1',
      'project-1',
      'mutation-1',
      0,
      { name: 'Kitchen cabinet', revision: 12 },
    );

    expect(transactionClient.project.create).toHaveBeenCalledWith({
      data: expect.objectContaining({
        id: 'project-1',
        ownerId: 'owner-1',
        name: 'Kitchen cabinet',
        revision: 1,
      }),
    });
    expect(result).toEqual(
      expect.objectContaining({
        mutationId: 'mutation-1',
        baseRevision: 0,
        appliedRevision: 1,
        status: 'APPLIED',
      }),
    );
  });

  test('subsequent sync increments only from the matching remote base', async () => {
    const { prisma, transactionClient } = createPrisma();
    prisma.syncMutation.findUnique.mockResolvedValue(null);
    prisma.project.findUnique.mockResolvedValue({
      id: 'project-1',
      ownerId: 'owner-1',
      revision: 4,
    });
    transactionClient.project.update.mockResolvedValue({ revision: 5 });
    transactionClient.syncMutation.create.mockImplementation(
      async ({ data }: { data: object }) => data,
    );
    const service = new ProjectsService(prisma as never);

    const result = await service.sync(
      'owner-1',
      'project-1',
      'mutation-2',
      4,
      { name: 'Updated cabinet' },
    );

    expect(transactionClient.project.update).toHaveBeenCalledWith({
      where: { id: 'project-1' },
      data: expect.objectContaining({
        name: 'Updated cabinet',
        revision: { increment: 1 },
      }),
    });
    expect(result).toEqual(expect.objectContaining({ appliedRevision: 5 }));
  });

  test('stale remote base returns a revision conflict', async () => {
    const { prisma } = createPrisma();
    prisma.syncMutation.findUnique.mockResolvedValue(null);
    prisma.project.findUnique.mockResolvedValue({
      id: 'project-1',
      ownerId: 'owner-1',
      revision: 5,
    });
    const service = new ProjectsService(prisma as never);

    await expect(
      service.sync('owner-1', 'project-1', 'mutation-3', 4, { name: 'Part' }),
    ).rejects.toBeInstanceOf(ConflictException);
  });

  test('idempotency keys never reveal another owners mutation', async () => {
    const { prisma } = createPrisma();
    prisma.syncMutation.findUnique.mockResolvedValue({
      mutationId: 'mutation-1',
      projectId: 'project-1',
      project: { ownerId: 'owner-2' },
    });
    const service = new ProjectsService(prisma as never);

    await expect(
      service.sync('owner-1', 'project-1', 'mutation-1', 0, { name: 'Part' }),
    ).rejects.toBeInstanceOf(NotFoundException);
  });

  test('accepts bounded advisory scan metadata in a synced manifest', async () => {
    const { prisma, transactionClient } = createPrisma();
    prisma.syncMutation.findUnique.mockResolvedValue(null);
    prisma.project.findUnique.mockResolvedValue(null);
    transactionClient.project.create.mockResolvedValue({ revision: 1 });
    transactionClient.syncMutation.create.mockImplementation(
      async ({ data }: { data: object }) => data,
    );
    const service = new ProjectsService(prisma as never);

    await expect(service.sync('owner-1', 'project-scan', 'mutation-scan', 0, {
      name: 'Measured cabinet',
      spatialScans: [{
        id: 'scan-1', sessionId: 'session-1', capturedAt: '2026-07-15T00:00:00.000Z',
        frameCount: 3, pointCount: 500, widthMm: 500, heightMm: 800,
        depthMm: 300, meanConfidence: 0.8, resolutionMm: 10,
      }],
    })).resolves.toEqual(expect.objectContaining({ status: 'APPLIED' }));
  });

  test('rejects raw point clouds in a project scan record', async () => {
    const { prisma } = createPrisma();
    const service = new ProjectsService(prisma as never);
    await expect(service.sync('owner-1', 'project-scan', 'mutation-raw', 0, {
      name: 'Unsafe scan',
      spatialScans: [{ id: 'scan-1', sessionId: 'session-1', capturedAt: 'now',
        frameCount: 1, pointCount: 3, widthMm: 1, heightMm: 1, depthMm: 1,
        meanConfidence: 1, resolutionMm: 1, points: [] }],
    })).rejects.toBeInstanceOf(BadRequestException);
    expect(prisma.syncMutation.findUnique).not.toHaveBeenCalled();
  });
});
describe('ProjectsService archive', () => {
  test('archives only an active project owned by the caller', async () => {
    const { prisma } = createPrisma();
    prisma.project.updateMany.mockResolvedValue({ count: 1 });
    const service = new ProjectsService(prisma as never);

    await expect(service.archive('owner-1', 'project-1')).resolves.toEqual({ success: true });
    expect(prisma.project.updateMany).toHaveBeenCalledWith({
      where: { id: 'project-1', ownerId: 'owner-1', status: 'ACTIVE' },
      data: { status: 'ARCHIVED' },
    });
  });

  test('does not reveal missing, inactive, or foreign projects', async () => {
    const { prisma } = createPrisma();
    prisma.project.updateMany.mockResolvedValue({ count: 0 });
    const service = new ProjectsService(prisma as never);

    await expect(service.archive('owner-1', 'foreign-project')).rejects
      .toBeInstanceOf(NotFoundException);
  });
});
describe('ProjectsService get', () => {
  test('returns only an active project owned by the caller', async () => {
    const { prisma } = createPrisma();
    prisma.project.findFirst.mockResolvedValue({
      id: 'project-1',
      ownerId: 'owner-1',
      revision: 3,
      manifest: { id: 'project-1' },
    });
    const service = new ProjectsService(prisma as never);

    const project = await service.get('owner-1', 'project-1');

    expect(prisma.project.findFirst).toHaveBeenCalledWith({
      where: {
        id: 'project-1',
        status: 'ACTIVE',
        OR: [{ ownerId: 'owner-1' }, { members: { some: { userId: 'owner-1' } } }],
      },
    });
    expect(project.revision).toBe(3);
  });

  test('missing or foreign projects return not found', async () => {
    const { prisma } = createPrisma();
    prisma.project.findFirst.mockResolvedValue(null);
    const service = new ProjectsService(prisma as never);

    await expect(service.get('owner-1', 'foreign-project')).rejects
      .toBeInstanceOf(NotFoundException);
  });
});

describe('ProjectsService changes', () => {
  test('returns only metadata for an owned active project history', async () => {
    const { prisma } = createPrisma();
    prisma.project.findFirst.mockResolvedValue({ id: 'project-1' });
    prisma.syncMutation.findMany.mockResolvedValue([{ mutationId: 'mutation-1' }]);
    const service = new ProjectsService(prisma as never);

    await expect(service.changes('owner-1', 'project-1')).resolves.toEqual([
      { mutationId: 'mutation-1' },
    ]);
    expect(prisma.syncMutation.findMany).toHaveBeenCalledWith({
      where: { projectId: 'project-1' },
      orderBy: { createdAt: 'desc' },
      select: {
        mutationId: true,
        baseRevision: true,
        appliedRevision: true,
        status: true,
        createdAt: true,
        actor: { select: { email: true, displayName: true } },
      },
    });
  });

  test('does not query history when project ownership check fails', async () => {
    const { prisma } = createPrisma();
    prisma.project.findFirst.mockResolvedValue(null);
    const service = new ProjectsService(prisma as never);

    await expect(service.changes('owner-1', 'foreign-project')).rejects
      .toBeInstanceOf(NotFoundException);
    expect(prisma.syncMutation.findMany).not.toHaveBeenCalled();
  });
});

describe('ProjectsService members', () => {
  test('owner can add a collaborator by email with a limited role', async () => {
    const { prisma } = createPrisma();
    prisma.project.findFirst.mockResolvedValue({ id: 'project-1', ownerId: 'owner-1' });
    prisma.project.findUnique.mockResolvedValue({ ownerId: 'owner-1' });
    prisma.user.findUnique.mockResolvedValue({ id: 'user-2', email: 'editor@example.com' });
    prisma.projectMember.findMany.mockResolvedValue([
      { role: 'EDITOR', user: { email: 'editor@example.com', displayName: 'Editor' } },
    ]);
    const service = new ProjectsService(prisma as never);

    await expect(service.addMember('owner-1', 'project-1', 'editor@example.com', 'EDITOR')).resolves.toEqual([
      { role: 'EDITOR', user: { email: 'editor@example.com', displayName: 'Editor' } },
    ]);
    expect(prisma.projectMember.upsert).toHaveBeenCalledWith(expect.objectContaining({
      where: { projectId_userId: { projectId: 'project-1', userId: 'user-2' } },
      update: { role: 'EDITOR' },
    }));
  });
});
