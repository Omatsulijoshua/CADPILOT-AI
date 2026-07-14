import { Body, Controller, Post } from '@nestjs/common';
import { IsEmail, IsString, MinLength } from 'class-validator';
import { AuthService } from './auth.service';
class RegisterDto { @IsEmail() email!: string; @IsString() @MinLength(8) password!: string; @IsString() @MinLength(2) displayName!: string; }
class LoginDto { @IsEmail() email!: string; @IsString() @MinLength(8) password!: string; }
class RefreshDto { @IsString() @MinLength(60) refreshToken!: string; }
@Controller('auth')
export class AuthController {
  constructor(private readonly auth: AuthService) {}
  @Post('register') register(@Body() dto: RegisterDto) { return this.auth.register(dto.email.toLowerCase(), dto.password, dto.displayName); }
  @Post('login') login(@Body() dto: LoginDto) { return this.auth.login(dto.email.toLowerCase(), dto.password); }
  @Post('refresh') refresh(@Body() dto: RefreshDto) { return this.auth.refresh(dto.refreshToken); }
  @Post('logout') logout(@Body() dto: RefreshDto) { return this.auth.logout(dto.refreshToken); }
}
