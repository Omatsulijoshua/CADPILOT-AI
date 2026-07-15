import 'dotenv/config';
import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';
import { configureHttpApp } from './http-config';
import { validateRuntimeConfig } from './runtime-config';

async function bootstrap() {
  const config = validateRuntimeConfig();
  const app = await NestFactory.create(AppModule, { bodyParser: false });
  configureHttpApp(app, config.corsAllowedOrigins, config.isProduction);
  await app.listen(config.port);
}
void bootstrap();
