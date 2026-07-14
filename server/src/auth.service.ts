import { ConflictException, Injectable, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { createHash, randomUUID } from 'crypto';
import * as argon2 from 'argon2';
import { PrismaService } from './prisma.service';

@Injectable()
export class AuthService {
  constructor(private readonly prisma: PrismaService, private readonly jwt: JwtService) {}
  private hashToken(token: string) { return createHash('sha256').update(token).digest('hex'); }
  private async issueTokens(user: { id: string; email: string; displayName: string }) {
    const accessToken = await this.jwt.signAsync({ sub: user.id, email: user.email });
    const refreshToken = `${randomUUID()}.${randomUUID()}`;
    await this.prisma.refreshToken.create({ data: { userId: user.id, tokenHash: this.hashToken(refreshToken), expiresAt: new Date(Date.now() + 30 * 86400000) } });
    return { user: { id: user.id, email: user.email, displayName: user.displayName }, accessToken, refreshToken, expiresIn: 900 };
  }
  async register(email: string, password: string, displayName: string) {
    if (await this.prisma.user.findUnique({ where: { email } })) throw new ConflictException('Email already registered');
    const user = await this.prisma.user.create({ data: { email, displayName, passwordHash: await argon2.hash(password, { type: argon2.argon2id }) } });
    return this.issueTokens(user);
  }
  async login(email: string, password: string) {
    const user = await this.prisma.user.findUnique({ where: { email } });
    if (!user || !(await argon2.verify(user.passwordHash, password))) throw new UnauthorizedException('Invalid credentials');
    return this.issueTokens(user);
  }
  async refresh(refreshToken: string) {
    const stored = await this.prisma.refreshToken.findUnique({ where: { tokenHash: this.hashToken(refreshToken) }, include: { user: true } });
    if (!stored || stored.revokedAt || stored.expiresAt <= new Date()) throw new UnauthorizedException('Refresh token is invalid or expired');
    await this.prisma.refreshToken.update({ where: { id: stored.id }, data: { revokedAt: new Date() } });
    return this.issueTokens(stored.user);
  }
  async logout(refreshToken: string) {
    await this.prisma.refreshToken.updateMany({ where: { tokenHash: this.hashToken(refreshToken), revokedAt: null }, data: { revokedAt: new Date() } });
    return { success: true };
  }
}
