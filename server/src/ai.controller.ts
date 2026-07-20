import { Body, Controller, Get, Post, Query, Req, UseGuards } from '@nestjs/common';
import { IsArray, IsObject, IsOptional, IsString, IsUUID, Length } from 'class-validator';
import { Throttle, ThrottlerGuard } from '@nestjs/throttler';
import { AccessTokenGuard, AuthenticatedRequest } from './auth.guard';
import { AiService } from './ai.service';

class GenerateCadCommandDto {
  @IsString() @Length(1, 2000) prompt!: string;
  @IsObject() context!: object;
  @IsUUID() @IsOptional() projectId?: string;
}
class GenerateCadPlanDto extends GenerateCadCommandDto {}
class GenerateCommandFromPlanDto extends GenerateCadCommandDto {
  @IsObject() plan!: object;
  @IsString() selectedOptionId!: string;
  @IsObject() @IsOptional() answers: object = {};
}
class SaveStarterTemplateDto {
  @IsString() @Length(1, 80) key!: string;
  @IsString() @Length(1, 120) title!: string;
  @IsString() @Length(1, 120) objectType!: string;
  @IsString() @Length(0, 500) @IsOptional() promptHint?: string;
  @IsArray() components!: unknown[];
}

@Controller('ai')
@UseGuards(ThrottlerGuard, AccessTokenGuard)
@Throttle({ default: { ttl: 60_000, limit: 10 } })
export class AiController {
  constructor(private readonly ai: AiService) {}

  @Post('commands')
  generate(@Req() request: AuthenticatedRequest, @Body() dto: GenerateCadCommandDto) {
    return this.ai.generateCommand(request.user.id, dto.prompt, dto.context, dto.projectId);
  }

  @Post('plans')
  plan(@Req() request: AuthenticatedRequest, @Body() dto: GenerateCadPlanDto) {
    return this.ai.generatePlan(request.user.id, dto.prompt, dto.context, dto.projectId);
  }

  @Post('plans/command')
  commandFromPlan(@Req() request: AuthenticatedRequest, @Body() dto: GenerateCommandFromPlanDto) {
    return this.ai.generateCommandFromPlan(request.user.id, dto.prompt, dto.plan, dto.selectedOptionId, dto.answers, dto.context, dto.projectId);
  }

  @Get('usage')
  usage(@Req() request: AuthenticatedRequest) {
    return this.ai.usageSummary(request.user.id);
  }

  @Get('starter-templates')
  starterTemplates(@Query('q') query?: string) {
    return this.ai.listStarterTemplates(query);
  }

  @Post('starter-templates')
  saveStarterTemplate(@Req() request: AuthenticatedRequest, @Body() dto: SaveStarterTemplateDto) {
    return this.ai.saveStarterTemplate(request.user.id, dto);
  }
}
