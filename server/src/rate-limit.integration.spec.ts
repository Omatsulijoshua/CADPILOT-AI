import { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { AddressInfo } from 'node:net';
import { AppModule } from './app.module';
import { configureHttpApp } from './http-config';
import { PrismaService } from './prisma.service';

describe('rate limiting', () => {
  let app: INestApplication;
  let baseUrl: string;

  beforeAll(async () => {
    const module = await Test.createTestingModule({ imports: [AppModule] })
      .overrideProvider(PrismaService)
      .useValue({})
      .compile();
    app = module.createNestApplication({ bodyParser: false, logger: false });
    configureHttpApp(app);
    await app.listen(0, '127.0.0.1');
    const address = app.getHttpServer().address() as AddressInfo;
    baseUrl = `http://127.0.0.1:${address.port}`;
  });

  afterAll(async () => {
    await app.close();
  });

  it('blocks the sixth invalid authentication request from one client within a minute', async () => {
    const responses = await Promise.all(
      Array.from({ length: 6 }, () => fetch(`${baseUrl}/v1/auth/register`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({}),
      })),
    );

    expect(responses.slice(0, 5).map((response) => response.status)).toEqual(
      [400, 400, 400, 400, 400],
    );
    expect(responses[5].status).toBe(429);
  });
});