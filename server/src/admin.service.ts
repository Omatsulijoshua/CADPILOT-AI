import { Injectable } from '@nestjs/common';
import { PrismaService } from './prisma.service';
import { AiProvider, Prisma } from '@prisma/client';
import { AiKeyVaultService } from './ai-key-vault.service';

@Injectable()
export class AdminService {
  constructor(private readonly prisma: PrismaService, private readonly vault: AiKeyVaultService = new AiKeyVaultService()) {}

  providerKeys() {
    return this.prisma.aiProviderKey.findMany({
      select: { id: true, provider: true, label: true, keyHint: true, enabled: true, priority: true, createdAt: true, updatedAt: true },
      orderBy: [{ provider: 'asc' }, { priority: 'asc' }, { createdAt: 'asc' }],
    });
  }

  async addProviderKeys(userId: string, provider: AiProvider, rawKeys: string, label: string, priority: number) {
    const keys = rawKeys.split(',').map(key => key.trim()).filter(Boolean);
    if (keys.length === 0 || keys.length > 20 || keys.some(key => key.length < 12 || key.length > 512)) {
      throw new Error('Provide between 1 and 20 valid API keys');
    }
    await this.prisma.aiProviderKey.createMany({ data: keys.map((key, index) => ({
      provider, label: keys.length === 1 ? label : `${label || provider} ${index + 1}`,
      encryptedKey: this.vault.encrypt(key), keyHint: this.vault.hint(key), priority: priority + index, createdById: userId,
    })) });
    return this.providerKeys();
  }

  async updateProviderKey(id: string, data: Prisma.AiProviderKeyUpdateInput) {
    await this.prisma.aiProviderKey.update({ where: { id }, data });
    return this.providerKeys();
  }

  async removeProviderKey(id: string) { await this.prisma.aiProviderKey.delete({ where: { id } }); return this.providerKeys(); }

  starterTemplates() {
    return this.prisma.aiStarterTemplate.findMany({
      select: {
        id: true, key: true, title: true, objectType: true, promptHint: true,
        components: true, uses: true, createdAt: true, updatedAt: true,
        createdBy: { select: { email: true, displayName: true } },
      },
      orderBy: [{ uses: 'desc' }, { updatedAt: 'desc' }],
      take: 100,
    });
  }

  async removeStarterTemplate(id: string) {
    await this.prisma.aiStarterTemplate.delete({ where: { id } });
    return this.starterTemplates();
  }

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
