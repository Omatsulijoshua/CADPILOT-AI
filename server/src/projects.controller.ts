import { Body, Controller, Delete, Get, Param, Post, Req, UseGuards } from '@nestjs/common';
import { IsInt, IsNotEmpty, IsObject, IsString, IsUUID, MaxLength, Min } from 'class-validator';
import { AccessTokenGuard, AuthenticatedRequest } from './auth.guard';
import { ProjectsService } from './projects.service';
class CreateProjectDto { @IsString() @IsNotEmpty() @MaxLength(80) name!: string; }
class SyncDto { @IsUUID() mutationId!: string; @IsInt() @Min(0) baseRevision!: number; @IsObject() payload!: object; }
@Controller('projects')
@UseGuards(AccessTokenGuard)
export class ProjectsController {
  constructor(private readonly projects: ProjectsService) {}
  @Get() list(@Req() request: AuthenticatedRequest) { return this.projects.list(request.user.id); }
  @Get(':id/changes') changes(@Req() request: AuthenticatedRequest, @Param('id') id: string) { return this.projects.changes(request.user.id, id); }
  @Get(':id') get(@Req() request: AuthenticatedRequest, @Param('id') id: string) { return this.projects.get(request.user.id, id); }
  @Post() create(@Req() request: AuthenticatedRequest, @Body() dto: CreateProjectDto) { return this.projects.create(request.user.id, dto.name); }
  @Delete(':id') archive(@Req() request: AuthenticatedRequest, @Param('id') id: string) { return this.projects.archive(request.user.id, id); }
  @Post(':id/sync') sync(@Req() request: AuthenticatedRequest, @Param('id') id: string, @Body() dto: SyncDto) { return this.projects.sync(request.user.id, id, dto.mutationId, dto.baseRevision, dto.payload); }
}
