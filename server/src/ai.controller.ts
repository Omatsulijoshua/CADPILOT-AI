import { Body, Controller, Post, Req, UseGuards } from '@nestjs/common';
import { IsObject, IsString, Length } from 'class-validator';
import { Throttle, ThrottlerGuard } from '@nestjs/throttler';
import { AccessTokenGuard, AuthenticatedRequest } from './auth.guard';
import { AiService } from './ai.service';

class GenerateCadCommandDto {
  @IsString() @Length(1, 2000) prompt!: string;
  @IsObject() context!: object;
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
}