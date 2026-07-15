import { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { AddressInfo } from 'node:net';
import { AppModule } from './app.module';
import { configureHttpApp } from './http-config';
import { PrismaService } from './prisma.service';

describe('CORS allowlist', () => {
  let app: INestApplication;
  let baseUrl: string;

  beforeAll(async () => {
    const module = await Test.createTestingModule({ imports: [AppModule] })
      .overrideProvider(PrismaService)
      .useValue({})
      .compile();
    app = module.createNestApplication({ bodyParser: false, logger: false });
    configureHttpApp(app, ['https://cadpilot.vercel.app']);
    await app.listen(0, '127.0.0.1');
    const address = app.getHttpServer().address() as AddressInfo;
    baseUrl = `http://127.0.0.1:${address.port}`;
  });

  afterAll(async () => {
    await app.close();
  });

  it('returns an allow-origin header only for an approved browser origin', async () => {
    const allowed = await fetch(`${baseUrl}/v1/health`, { headers: { origin: 'https://cadpilot.vercel.app' } });
    const rejected = await fetch(`${baseUrl}/v1/health`, { headers: { origin: 'https://untrusted.example' } });

    expect(allowed.headers.get('access-control-allow-origin')).toBe('https://cadpilot.vercel.app');
    expect(rejected.headers.get('access-control-allow-origin')).toBeNull();
  });
});