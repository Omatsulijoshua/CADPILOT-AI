import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { ThrottlerModule } from '@nestjs/throttler';
import { AiController } from './ai.controller';
import { AiService } from './ai.service';
import { AdminController } from './admin.controller';
import { AdminService } from './admin.service';
import { AuthController } from './auth.controller';
import { AccessTokenGuard } from './auth.guard';
import { AuthService } from './auth.service';
import { HealthController } from './health.controller';
import { PrismaService } from './prisma.service';
import { ProjectsController } from './projects.controller';
import { ProjectsService } from './projects.service';
import { SuperAdminGuard } from './super-admin.guard';

@Module({
  imports: [
    JwtModule.register({
      secret: process.env.JWT_ACCESS_SECRET ?? 'development-only-access-secret-change-me',
      signOptions: { expiresIn: '15m', issuer: 'cadpilot-api', audience: 'cadpilot-tablet' },
    }),
    ThrottlerModule.forRoot([{ name: 'default', ttl: 60_000, limit: 100 }]),
  ],
  controllers: [HealthController, AuthController, ProjectsController, AiController, AdminController],
  providers: [PrismaService, AuthService, ProjectsService, AiService, AdminService, AccessTokenGuard, SuperAdminGuard],
})
export class AppModule {}
