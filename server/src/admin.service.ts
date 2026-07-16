import { Injectable } from '@nestjs/common';
import { PrismaService } from './prisma.service';

@Injectable()
export class AdminService {
  constructor(private readonly prisma: PrismaService) {}

  async overview() {
    const [users, activeProjects, archivedProjects, mutations, aiUsage] = await Promise.all([
      this.prisma.user.count(),
      this.prisma.project.count({ where: { status: 'ACTIVE' } }),
      this.prisma.project.count({ where: { status: 'ARCHIVED' } }),
      this.prisma.syncMutation.count(),
      this.prisma.aiUsage.aggregate({ _sum: { totalTokens: true }, _count: { _all: true } }),
    ]);
    return {
      users,
      activeProjects,
      archivedProjects,
      mutations,
      aiRequests: aiUsage._count._all,
      aiTokens: aiUsage._sum.totalTokens ?? 0,
    };
  }

  users() {
    return this.prisma.user.findMany({
      select: {
        id: true, email: true, displayName: true, createdAt: true, updatedAt: true,
        _count: { select: { projects: true, refreshTokens: true } },
      },
      orderBy: { createdAt: 'desc' },
      take: 100,
    });
  }

  projects() {
    return this.prisma.project.findMany({
      select: {
        id: true, name: true, status: true, revision: true, createdAt: true, updatedAt: true,
        owner: { select: { email: true, displayName: true } },
      },
      orderBy: { updatedAt: 'desc' },
      take: 100,
    });
  }

  async audit() {
    const [aiUsage, mutations] = await Promise.all([
      this.prisma.aiUsage.findMany({
        select: {
          id: true, provider: true, model: true, totalTokens: true, createdAt: true,
          user: { select: { email: true, displayName: true } },
        },
        orderBy: { createdAt: 'desc' },
        take: 100,
      }),
      this.prisma.syncMutation.findMany({
        select: {
          id: true, status: true, baseRevision: true, appliedRevision: true, createdAt: true,
          project: { select: { name: true } },
        },
        orderBy: { createdAt: 'desc' },
        take: 100,
      }),
    ]);
    return { aiUsage, mutations };
  }
}
