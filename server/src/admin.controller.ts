import { Body, Controller, Delete, Get, Param, Patch, Post, UseGuards } from '@nestjs/common';
import { IsBoolean, IsEnum, IsInt, IsOptional, IsString, Max, Min, MinLength } from 'class-validator';
import { AiProvider } from '@prisma/client';
import { AuthenticatedRequest } from './auth.guard';
import { Req } from '@nestjs/common';
class AddProviderKeysDto { @IsEnum(AiProvider) provider!: AiProvider; @IsString() @MinLength(12) keys!: string; @IsString() @IsOptional() label = ''; @IsInt() @Min(0) @Max(1000) @IsOptional() priority = 0; }
class UpdateProviderKeyDto { @IsBoolean() @IsOptional() enabled?: boolean; @IsInt() @Min(0) @Max(1000) @IsOptional() priority?: number; }
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
  @Get('audit') audit() { return this.admin.audit(); }
  @Get('ai/providers') providerKeys() { return this.admin.providerKeys(); }
  @Post('ai/providers') addProviderKeys(@Req() request: AuthenticatedRequest, @Body() dto: AddProviderKeysDto) { return this.admin.addProviderKeys(request.user.id, dto.provider, dto.keys, dto.label, dto.priority); }
  @Patch('ai/providers/:id') updateProviderKey(@Param('id') id: string, @Body() dto: UpdateProviderKeyDto) { return this.admin.updateProviderKey(id, dto); }
  @Delete('ai/providers/:id') removeProviderKey(@Param('id') id: string) { return this.admin.removeProviderKey(id); }
}
