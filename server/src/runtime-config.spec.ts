import { validateRuntimeConfig } from './runtime-config';

const productionSecrets = {
  NODE_ENV: 'production',
  JWT_ACCESS_SECRET: 'a-unique-production-access-secret-that-is-long-enough',
  JWT_REFRESH_SECRET: 'a-unique-production-refresh-secret-that-is-long-enough',
};

describe('runtime configuration validation', () => {
  it('keeps development startup convenient with the default port', () => {
    expect(validateRuntimeConfig({ NODE_ENV: 'development' })).toEqual({ port: 3000 });
  });

  it('accepts independent production secrets and a valid port', () => {
    expect(validateRuntimeConfig({ ...productionSecrets, PORT: '8080' })).toEqual({ port: 8080 });
  });

  it.each(['', 'replace-with-a-long-random-access-secret', 'development-only-access-secret-change-me', 'short-secret'])('rejects an unsafe production access secret: %s', (secret) => {
    expect(() => validateRuntimeConfig({ ...productionSecrets, JWT_ACCESS_SECRET: secret })).toThrow(
      'JWT_ACCESS_SECRET must be a unique, non-placeholder secret of at least 32 characters in production',
    );
  });

  it('rejects equal production token secrets', () => {
    expect(() => validateRuntimeConfig({
      ...productionSecrets,
      JWT_REFRESH_SECRET: productionSecrets.JWT_ACCESS_SECRET,
    })).toThrow('JWT_ACCESS_SECRET and JWT_REFRESH_SECRET must be different in production');
  });

  it.each(['0', '65536', 'not-a-port'])('rejects an invalid port: %s', (port) => {
    expect(() => validateRuntimeConfig({ PORT: port })).toThrow('PORT must be an integer from 1 through 65535');
  });
});