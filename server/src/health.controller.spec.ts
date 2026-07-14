import { HealthController } from './health.controller';

describe('HealthController', () => {
  it('reports the active foundation phase', () => {
    expect(new HealthController().check()).toEqual({ status: 'ok', phase: 1 });
  });
});
