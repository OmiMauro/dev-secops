/**
 * Valida las variables de entorno al arrancar.
 * Si falta alguna, la app no arranca: es mejor fallar pronto
 * que descubrir en producción que JWT_SECRET estaba vacío.
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
    throw new Error(`Faltan variables de entorno: ${missing.join(', ')}`);
  }

  const jwtSecret = String(config.JWT_SECRET);
  if (jwtSecret.length < MIN_JWT_SECRET_LENGTH) {
    throw new Error(
      `JWT_SECRET debe tener al menos ${MIN_JWT_SECRET_LENGTH} caracteres`,
    );
  }

  return config;
}
