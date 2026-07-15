import { ServiceUnavailableException } from '@nestjs/common';
import { HealthController } from './health.controller';

const queryRaw = jest.fn();
const controller = new HealthController({ $queryRaw: queryRaw } as never);

describe('HealthController', () => {
  beforeEach(() => queryRaw.mockReset());

  it('reports the active foundation phase for liveness checks', () => {
    expect(controller.check()).toEqual({ status: 'ok', phase: 1 });
  });

  it('reports ready only after the database accepts a minimal query', async () => {
    queryRaw.mockResolvedValue([{ '?column?': 1 }]);

    await expect(controller.ready()).resolves.toEqual({ status: 'ready' });
    expect(queryRaw).toHaveBeenCalledTimes(1);
  });

  it('returns a safe unavailable response when the database cannot be reached', async () => {
    queryRaw.mockRejectedValue(new Error('connection refused'));

    await expect(controller.ready()).rejects.toBeInstanceOf(
      ServiceUnavailableException,
    );
  });
});