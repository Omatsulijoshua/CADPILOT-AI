import type { Request, Response } from 'express';
import { NestFactory } from '@nestjs/core';
import { AppModule } from '../src/app.module';
import { configureHttpApp } from '../src/http-config';
import { validateRuntimeConfig } from '../src/runtime-config';

type ExpressHandler = (request: Request, response: Response) => void;

let handlerPromise: Promise<ExpressHandler> | undefined;

async function appHandler(): Promise<ExpressHandler> {
  if (!handlerPromise) {
    handlerPromise = (async () => {
      const config = validateRuntimeConfig();
      const app = await NestFactory.create(AppModule, { bodyParser: false });
      configureHttpApp(app, config.corsAllowedOrigins, config.isProduction);
      await app.init();
      return app.getHttpAdapter().getInstance() as ExpressHandler;
    })();
  }
  return handlerPromise;
}

export default async function handler(request: Request, response: Response) {
  const path = request.query.path;
  if (typeof path === 'string') request.url = `/${path}`;
  return (await appHandler())(request, response);
}
