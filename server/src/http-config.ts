import { INestApplication, ValidationPipe } from '@nestjs/common';
import { json, urlencoded } from 'express';

export const REQUEST_BODY_LIMIT = '2mb';

export function configureHttpApp(app: INestApplication, corsAllowedOrigins: string[] = []): void {
  app.use(json({ limit: REQUEST_BODY_LIMIT }));
  app.use(urlencoded({ extended: false, limit: REQUEST_BODY_LIMIT }));
  if (corsAllowedOrigins.length > 0) {
    app.enableCors({ origin: corsAllowedOrigins, credentials: false });
  }
  app.setGlobalPrefix('v1');
  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: true,
      transform: true,
    }),
  );
}
