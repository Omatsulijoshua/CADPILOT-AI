import { ConflictException, Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from './prisma.service';

@Injectable()
export class ProjectsService {
  constructor(private readonly prisma: PrismaService) {}
  list(ownerId: string) { return this.prisma.project.findMany({ where: { ownerId, status: 'ACTIVE' }, orderBy: { updatedAt: 'desc' } }); }
  create(ownerId: string, name: string) { return this.prisma.project.create({ data: { ownerId, name, manifest: { formatVersion: 1, operations: [] } } }); }
  async sync(ownerId: string, projectId: string, mutationId: string, baseRevision: number, payload: object) {
    const existing = await this.prisma.syncMutation.findUnique({ where: { mutationId } });
    if (existing) return existing;
    const project = await this.prisma.project.findFirst({ where: { id: projectId, ownerId } });
    if (!project) throw new NotFoundException('Project not found');
    if (project.revision !== baseRevision) throw new ConflictException({ code: 'REVISION_CONFLICT', currentRevision: project.revision });
    return this.prisma.$transaction(async (tx) => {
      const updated = await tx.project.update({ where: { id: projectId }, data: { revision: { increment: 1 }, manifest: payload } });
      return tx.syncMutation.create({ data: { mutationId, projectId, baseRevision, appliedRevision: updated.revision, payload, status: 'APPLIED' } });
    });
  }
}
