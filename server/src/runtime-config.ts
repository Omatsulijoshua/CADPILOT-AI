const DEVELOPMENT_ACCESS_SECRET = 'development-only-access-secret-change-me';
const PLACEHOLDER_MARKERS = ['replace-with-', 'change-me', 'development-only'];

export interface RuntimeConfig {
  port: number;
  corsAllowedOrigins: string[];
  isProduction: boolean;
}

function requiredProductionSecret(environment: NodeJS.ProcessEnv, name: string): void {
  const value = environment[name]?.trim();
  if (!value || value.length < 32 || PLACEHOLDER_MARKERS.some((marker) => value.toLowerCase().includes(marker))) {
    throw new Error(`${name} must be a unique, non-placeholder secret of at least 32 characters in production`);
  }
}

function productionCorsOrigins(environment: NodeJS.ProcessEnv): string[] {
  const values = environment.CORS_ALLOWED_ORIGINS?.split(',').map((value) => value.trim()).filter(Boolean) ?? [];
  if (values.length === 0) {
    throw new Error('CORS_ALLOWED_ORIGINS must list at least one HTTPS browser origin in production');
  }

  return [...new Set(values)].map((value) => {
    let url: URL;
    try {
      url = new URL(value);
    } catch {
      throw new Error('CORS_ALLOWED_ORIGINS must contain valid HTTPS origins');
    }
    if (url.protocol !== 'https:' || url.origin !== value) {
      throw new Error('CORS_ALLOWED_ORIGINS must contain valid HTTPS origins without paths');
    }
    return value;
  });
}

export function validateRuntimeConfig(environment: NodeJS.ProcessEnv = process.env): RuntimeConfig {
  const rawPort = environment.PORT ?? '3000';
  const port = Number(rawPort);
  if (!Number.isInteger(port) || port < 1 || port > 65_535) {
    throw new Error('PORT must be an integer from 1 through 65535');
  }

  const isProduction = environment.NODE_ENV === 'production';
  if (isProduction) {
    requiredProductionSecret(environment, 'JWT_ACCESS_SECRET');
    requiredProductionSecret(environment, 'JWT_REFRESH_SECRET');
    if (environment.JWT_ACCESS_SECRET === environment.JWT_REFRESH_SECRET) {
      throw new Error('JWT_ACCESS_SECRET and JWT_REFRESH_SECRET must be different in production');
    }
  }

  return { port, corsAllowedOrigins: isProduction ? productionCorsOrigins(environment) : [], isProduction };
}

export { DEVELOPMENT_ACCESS_SECRET };