import { CanActivate, ExecutionContext, Injectable, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import type { Request } from 'express';
export interface AuthenticatedRequest extends Request { user: { id: string; email: string }; }
@Injectable()
export class AccessTokenGuard implements CanActivate {
  constructor(private readonly jwt: JwtService) {}
  async canActivate(context: ExecutionContext) {
    const request = context.switchToHttp().getRequest<AuthenticatedRequest>();
    const [scheme, token] = request.headers.authorization?.split(' ') ?? [];
    if (scheme !== 'Bearer' || !token) throw new UnauthorizedException('Bearer token required');
    try {
      const payload = await this.jwt.verifyAsync<{ sub: string; email: string }>(token, { issuer: 'cadpilot-api', audience: 'cadpilot-tablet' });
      request.user = { id: payload.sub, email: payload.email };
      return true;
    } catch { throw new UnauthorizedException('Access token is invalid or expired'); }
  }
}
