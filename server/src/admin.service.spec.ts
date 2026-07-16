import { ForbiddenException } from '@nestjs/common';
import { AdminService } from './admin.service';
import { SuperAdminGuard } from './super-admin.guard';

describe('AdminService', () => {
  test('returns aggregate metrics without exposing user credentials', async () => {
    const prisma = {
      user: { count: jest.fn().mockResolvedValue(4) },
      project: { count: jest.fn().mockResolvedValueOnce(6).mockResolvedValueOnce(2) },
      syncMutation: { count: jest.fn().mockResolvedValue(9) },
      aiUsage: { aggregate: jest.fn().mockResolvedValue({ _sum: { totalTokens: 1200 }, _count: { _all: 3 } }) },
    };
    await expect(new AdminService(prisma as never).overview()).resolves.toEqual({
      users: 4, activeProjects: 6, archivedProjects: 2, mutations: 9,
      aiRequests: 3, aiTokens: 1200,
    });
  });
});

describe('SuperAdminGuard', () => {
  const original = process.env.CADPILOT_SUPER_ADMIN_EMAILS;
  afterEach(() => { process.env.CADPILOT_SUPER_ADMIN_EMAILS = original; });

  test('permits only an email in the configured allowlist', () => {
    process.env.CADPILOT_SUPER_ADMIN_EMAILS = 'owner@example.com, admin@example.com';
    const context = { switchToHttp: () => ({ getRequest: () => ({ user: { email: 'ADMIN@example.com' } }) }) };
    expect(new SuperAdminGuard().canActivate(context as never)).toBe(true);
  });

  test('fails closed when no administrator is configured', () => {
    delete process.env.CADPILOT_SUPER_ADMIN_EMAILS;
    const context = { switchToHttp: () => ({ getRequest: () => ({ user: { email: 'owner@example.com' } }) }) };
    expect(() => new SuperAdminGuard().canActivate(context as never)).toThrow(ForbiddenException);
  });
});
