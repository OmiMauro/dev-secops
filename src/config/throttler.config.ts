import { ThrottlerModuleOptions } from '@nestjs/throttler';

const ONE_MINUTE_MS = 60_000;

/**
 * Reads a positive integer from the environment, or returns the default.
 * Read on every request, so the value can come from Vault or the container
 * environment without any import-order concerns.
 */
function limitFromEnv(name: string, fallback: number): () => number {
  return () => {
    const value = Number(process.env[name]);
    return Number.isInteger(value) && value > 0 ? value : fallback;
  };
}

/**
 * Rate limiting, counted per client IP.
 *
 * Default for every route: 100 requests per minute (THROTTLE_LIMIT).
 * Generous for a real client, but it stops a single IP from flooding the
 * API. The auth routes use a much stricter limit, see AUTH_THROTTLE.
 *
 * Counters live in memory, which is fine for ONE instance. With several
 * instances behind a load balancer each one counts separately, so the
 * real limit multiplies; use a shared store (e.g. Redis) there.
 *
 * Behind a proxy or load balancer every request arrives from the proxy's
 * IP, so all clients would share one counter. Express then needs
 * `app.set('trust proxy', <number of proxies>)` to read the client IP from
 * X-Forwarded-For. Only enable it when a proxy really is in front: without
 * one, any client can send a fake X-Forwarded-For and dodge the limit.
 */
export const throttlerConfig: ThrottlerModuleOptions = [
  {
    name: 'default',
    ttl: ONE_MINUTE_MS,
    limit: limitFromEnv('THROTTLE_LIMIT', 100),
  },
];

/**
 * Login and register: 5 attempts per minute per IP (AUTH_THROTTLE_LIMIT).
 * A password-guessing attack goes from thousands of attempts a minute to
 * five.
 *
 * Both limits can be raised only for the DAST test environment, where the
 * scanner must send hundreds of attacks to the same routes. Never raise
 * them in production.
 */
export const AUTH_THROTTLE = {
  default: {
    ttl: ONE_MINUTE_MS,
    limit: limitFromEnv('AUTH_THROTTLE_LIMIT', 5),
  },
};
