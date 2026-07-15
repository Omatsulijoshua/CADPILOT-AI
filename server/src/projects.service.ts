import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { PrismaService } from './prisma.service';

@Injectable()
export class ProjectsService {
  private static readonly maxManifestBytes = 2 * 1024 * 1024;
  private static readonly maxSpatialScanRecords = 500;

  constructor(private readonly prisma: PrismaService) {}

  list(ownerId: string) {
    return this.prisma.project.findMany({
      where: { ownerId, status: 'ACTIVE' },
      orderBy: { updatedAt: 'desc' },
    });
  }

  async get(ownerId: string, projectId: string) {
    const project = await this.prisma.project.findFirst({
      where: { id: projectId, ownerId, status: 'ACTIVE' },
    });
    if (!project) throw new NotFoundException('Project not found');
    return project;
  }
  async archive(ownerId: string, projectId: string) {
    const result = await this.prisma.project.updateMany({
      where: { id: projectId, ownerId, status: 'ACTIVE' },
      data: { status: 'ARCHIVED' },
    });
    if (result.count !== 1) throw new NotFoundException('Project not found');
    return { success: true };
  }
  create(ownerId: string, name: string) {
    const normalizedName = name.trim() || 'Untitled design';
    return this.prisma.project.create({
      data: {
        ownerId,
        name: normalizedName,
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
    this.validateManifest(payload);
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

  private validateManifest(payload: object): void {
    let encoded: string;
    try {
      encoded = JSON.stringify(payload);
    } catch {
      throw new BadRequestException('Project manifest must be JSON serializable');
    }
    if (Buffer.byteLength(encoded, 'utf8') > ProjectsService.maxManifestBytes) {
      throw new BadRequestException('Project manifest exceeds the 2 MiB limit');
    }

    const scans = (payload as Record<string, unknown>).spatialScans;
    if (scans === undefined) return;
    if (!Array.isArray(scans) || scans.length > ProjectsService.maxSpatialScanRecords) {
      throw new BadRequestException('Spatial scan records must be a bounded array');
    }
    for (const scan of scans) this.validateSpatialScanRecord(scan);
  }

  private validateSpatialScanRecord(value: unknown): void {
    if (!value || typeof value !== 'object' || Array.isArray(value)) {
      throw new BadRequestException('Spatial scan record must be an object');
    }
    const scan = value as Record<string, unknown>;
    if ('points' in scan || 'pointCloud' in scan || 'rawDepth' in scan || 'depthImage' in scan) {
      throw new BadRequestException('Raw spatial capture data cannot be synced in a project manifest');
    }
    for (const field of ['id', 'sessionId', 'capturedAt']) {
      if (typeof scan[field] !== 'string' || scan[field].trim().length === 0) {
        throw new BadRequestException(`Spatial scan ${field} is required`);
      }
    }
    for (const field of [
      'frameCount',
      'pointCount',
      'widthMm',
      'heightMm',
      'depthMm',
      'meanConfidence',
      'resolutionMm',
    ]) {
      if (typeof scan[field] !== 'number' || !Number.isFinite(scan[field])) {
        throw new BadRequestException(`Spatial scan ${field} must be finite`);
      }
    }
    if (
      (scan.frameCount as number) < 1 ||
      (scan.pointCount as number) < 3 ||
      (scan.widthMm as number) < 0 ||
      (scan.heightMm as number) < 0 ||
      (scan.depthMm as number) < 0 ||
      (scan.meanConfidence as number) < 0 ||
      (scan.meanConfidence as number) > 1 ||
      (scan.resolutionMm as number) <= 0
    ) {
      throw new BadRequestException('Spatial scan record has invalid bounds');
    }
  }
}
