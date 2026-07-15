import { ConflictException, Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from './prisma.service';

@Injectable()
export class ProjectsService {
  constructor(private readonly prisma: PrismaService) {}

  list(ownerId: string) {
    return this.prisma.project.findMany({
      where: { ownerId, status: 'ACTIVE' },
      orderBy: { updatedAt: 'desc' },
    });
  }

  create(ownerId: string, name: string) {
    return this.prisma.project.create({
      data: {
        ownerId,
        name,
        manifest: { formatVersion: 1, operations: [] },
      },
    });
  }

  async sync(
    ownerId: string,
    projectId: string,
    mutationId: string,
    baseRevision: number,
    payload: object,
  ) {
    const existingMutation = await this.prisma.syncMutation.findUnique({
      where: { mutationId },
      include: { project: { select: { ownerId: true } } },
    });
    if (existingMutation) {
      if (
        existingMutation.projectId !== projectId ||
        existingMutation.project.ownerId !== ownerId
      ) {
        throw new NotFoundException('Project not found');
      }
      return existingMutation;
    }

    const project = await this.prisma.project.findUnique({
      where: { id: projectId },
    });
    if (project && project.ownerId !== ownerId) {
      throw new NotFoundException('Project not found');
    }

    if (!project) {
      if (baseRevision !== 0) {
        throw new ConflictException({
          code: 'REVISION_CONFLICT',
          currentRevision: 0,
        });
      }
      const name = this.projectName(payload);
      return this.prisma.$transaction(async (tx) => {
        const created = await tx.project.create({
          data: {
            id: projectId,
            ownerId,
            name,
            revision: 1,
            manifest: payload,
          },
        });
        return tx.syncMutation.create({
          data: {
            mutationId,
            projectId,
            baseRevision: 0,
            appliedRevision: created.revision,
            payload,
            status: 'APPLIED',
          },
        });
      });
    }

    if (project.revision !== baseRevision) {
      throw new ConflictException({
        code: 'REVISION_CONFLICT',
        currentRevision: project.revision,
      });
    }

    return this.prisma.$transaction(async (tx) => {
      const updated = await tx.project.update({
        where: { id: projectId },
        data: {
          name: this.projectName(payload),
          revision: { increment: 1 },
          manifest: payload,
        },
      });
      return tx.syncMutation.create({
        data: {
          mutationId,
          projectId,
          baseRevision,
          appliedRevision: updated.revision,
          payload,
          status: 'APPLIED',
        },
      });
    });
  }

  private projectName(payload: object): string {
    const value = (payload as Record<string, unknown>).name;
    return typeof value === 'string' && value.trim().length > 0
      ? value.trim()
      : 'Untitled design';
  }
}
