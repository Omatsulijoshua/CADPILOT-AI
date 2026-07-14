import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { AiController } from './ai.controller';
import { AiService } from './ai.service';
import { AuthController } from './auth.controller';
import { AccessTokenGuard } from './auth.guard';
import { AuthService } from './auth.service';
import { HealthController } from './health.controller';
import { PrismaService } from './prisma.service';
import { ProjectsController } from './projects.controller';
import { ProjectsService } from './projects.service';

@Module({
  imports: [JwtModule.register({
    secret: process.env.JWT_ACCESS_SECRET ?? 'development-only-access-secret-change-me',
    signOptions: { expiresIn: '15m', issuer: 'cadpilot-api', audience: 'cadpilot-tablet' },
  })],
  controllers: [HealthController, AuthController, ProjectsController, AiController],
  providers: [PrismaService, AuthService, ProjectsService, AiService, AccessTokenGuard],
})
export class AppModule {}
