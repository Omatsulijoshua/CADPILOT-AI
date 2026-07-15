import { ConflictException, NotFoundException } from '@nestjs/common';
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
      },
      syncMutation: {
        findUnique: jest.fn(),
      },
      $transaction: jest.fn(
        (operation: (tx: typeof transactionClient) => unknown) =>
          operation(transactionClient),
      ),
    },
  };
}

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
      where: { id: 'project-1', ownerId: 'owner-1', status: 'ACTIVE' },
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