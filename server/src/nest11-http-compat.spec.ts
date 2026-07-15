import { INestApplication, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { AddressInfo } from 'node:net';
import { AppModule } from './app.module';
import { PrismaService } from './prisma.service';

describe('NestJS 11 HTTP compatibility', () => {
  let app: INestApplication;
  let baseUrl: string;

  beforeAll(async () => {
const module = await Test.createTestingModule({ imports: [AppModule] })
      .overrideProvider(PrismaService)
      .useValue({})
      .compile();
    app = module.createNestApplication({ logger: false });
    app.setGlobalPrefix('v1');
    app.useGlobalPipes(new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: true,
      transform: true,
    }));
    await app.listen(0, '127.0.0.1');
    const address = app.getHttpServer().address() as AddressInfo;
    baseUrl = `http://127.0.0.1:${address.port}`;
  });

  afterAll(async () => {
    await app.close();
  });

  it('serves the globally prefixed health route through Express 5', async () => {
    const response = await fetch(`${baseUrl}/v1/health`);

    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toEqual(
      expect.objectContaining({ status: 'ok' }),
    );
  });

  it('preserves the access-token guard on protected project routes', async () => {
    const response = await fetch(`${baseUrl}/v1/projects`);

    expect(response.status).toBe(401);
    await expect(response.json()).resolves.toEqual(
      expect.objectContaining({ message: 'Bearer token required' }),
    );
  });

  it('rejects unknown request fields before authentication service work', async () => {
    const response = await fetch(`${baseUrl}/v1/auth/register`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        email: 'designer@example.com',
        password: 'password123',
        displayName: 'Designer',
        unexpected: true,
      }),
    });

    expect(response.status).toBe(400);
    await expect(response.json()).resolves.toEqual(
      expect.objectContaining({
        message: expect.arrayContaining([
          'property unexpected should not exist',
        ]),
      }),
    );
  });
});