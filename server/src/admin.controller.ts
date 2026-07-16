import { Controller, Get, UseGuards } from '@nestjs/common';
import { AccessTokenGuard } from './auth.guard';
import { AdminService } from './admin.service';
import { SuperAdminGuard } from './super-admin.guard';

@Controller('admin')
@UseGuards(AccessTokenGuard, SuperAdminGuard)
export class AdminController {
  constructor(private readonly admin: AdminService) {}

  @Get('overview') overview() { return this.admin.overview(); }
  @Get('users') users() { return this.admin.users(); }
  @Get('projects') projects() { return this.admin.projects(); }
}
