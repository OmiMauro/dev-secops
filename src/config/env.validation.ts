/**
 * Validates environment variables at startup.
 * If one is missing the app refuses to start: failing early is better
 * than finding out in production that JWT_SECRET was empty.
 */
const REQUIRED_VARS = [
  'DB_HOST',
  'DB_PORT',
  'DB_USER',
  'DB_PASSWORD',
  'DB_NAME',
  'JWT_SECRET',
] as const;

const MIN_JWT_SECRET_LENGTH = 32;

export function validateEnv(config: Record<string, unknown>) {
  const missing = REQUIRED_VARS.filter((name) => !config[name]);
  if (missing.length > 0) {
    throw new Error(`Missing environment variables: ${missing.join(', ')}`);
  }

  const jwtSecret = String(config.JWT_SECRET);
  if (jwtSecret.length < MIN_JWT_SECRET_LENGTH) {
    throw new Error(
      `JWT_SECRET must be at least ${MIN_JWT_SECRET_LENGTH} characters long`,
    );
  }

  return config;
}
