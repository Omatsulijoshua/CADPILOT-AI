import { Body, Controller, Post, Req, UseGuards } from '@nestjs/common';
import { IsObject, IsOptional, IsString, Length } from 'class-validator';
import { Throttle, ThrottlerGuard } from '@nestjs/throttler';
import { AccessTokenGuard, AuthenticatedRequest } from './auth.guard';
import { AiService } from './ai.service';

class GenerateCadCommandDto {
  @IsString() @Length(1, 2000) prompt!: string;
  @IsObject() context!: object;
}
class GenerateCadPlanDto extends GenerateCadCommandDto {}
class GenerateCommandFromPlanDto extends GenerateCadCommandDto {
  @IsObject() plan!: object;
  @IsString() selectedOptionId!: string;
  @IsObject() @IsOptional() answers: object = {};
}

@Controller('ai')
@UseGuards(ThrottlerGuard, AccessTokenGuard)
@Throttle({ default: { ttl: 60_000, limit: 10 } })
export class AiController {
  constructor(private readonly ai: AiService) {}

  @Post('commands')
  generate(@Req() request: AuthenticatedRequest, @Body() dto: GenerateCadCommandDto) {
    return this.ai.generateCommand(request.user.id, dto.prompt, dto.context);
  }

  @Post('plans')
  plan(@Req() request: AuthenticatedRequest, @Body() dto: GenerateCadPlanDto) {
    return this.ai.generatePlan(request.user.id, dto.prompt, dto.context);
  }

  @Post('plans/command')
  commandFromPlan(@Req() request: AuthenticatedRequest, @Body() dto: GenerateCommandFromPlanDto) {
    return this.ai.generateCommandFromPlan(request.user.id, dto.prompt, dto.plan, dto.selectedOptionId, dto.answers, dto.context);
  }
}
