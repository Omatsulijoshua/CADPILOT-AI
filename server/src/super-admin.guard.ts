import { CanActivate, ExecutionContext, ForbiddenException, Injectable } from '@nestjs/common';
import { AuthenticatedRequest } from './auth.guard';

@Injectable()
export class SuperAdminGuard implements CanActivate {
  canActivate(context: ExecutionContext) {
    const request = context.switchToHttp().getRequest<AuthenticatedRequest>();
    const allowlist = (process.env.CADPILOT_SUPER_ADMIN_EMAILS ?? '')
      .split(',')
      .map((email) => email.trim().toLowerCase())
      .filter(Boolean);
    if (!allowlist.includes(request.user.email.toLowerCase())) {
      throw new ForbiddenException('Super-admin access is required');
    }
    return true;
  }
}
