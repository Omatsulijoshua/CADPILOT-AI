import { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { AddressInfo } from 'node:net';
import { AppModule } from './app.module';
import { configureHttpApp } from './http-config';
import { PrismaService } from './prisma.service';

describe('security response headers', () => {
  let app: INestApplication;
  let baseUrl: string;

  beforeAll(async () => {
    const module = await Test.createTestingModule({ imports: [AppModule] })
      .overrideProvider(PrismaService)
      .useValue({})
      .compile();
    app = module.createNestApplication({ bodyParser: false, logger: false });
    configureHttpApp(app, [], true);
    await app.listen(0, '127.0.0.1');
    const address = app.getHttpServer().address() as AddressInfo;
    baseUrl = `http://127.0.0.1:${address.port}`;
  });

  afterAll(async () => {
    await app.close();
  });

  it('sets standard defensive headers before serving API responses', async () => {
    const response = await fetch(`${baseUrl}/v1/health`);

    expect(response.headers.get('content-security-policy')).toContain("default-src 'self'");
    expect(response.headers.get('strict-transport-security')).toContain('max-age=');
    expect(response.headers.get('x-content-type-options')).toBe('nosniff');
    expect(response.headers.get('x-frame-options')).toBe('SAMEORIGIN');
    expect(response.headers.get('x-powered-by')).toBeNull();
  });
});