/**
 * Loads secrets from HashiCorp Vault into process.env at startup.
 *
 * Flow (AppRole auth):
 *   1. log in with VAULT_ROLE_ID + VAULT_SECRET_ID → short-lived token
 *   2. read the KV v2 secret at VAULT_SECRET_PATH with that token
 *   3. copy every key/value into process.env (DB_PASSWORD, JWT_SECRET...)
 *
 * If VAULT_ADDR is not set, nothing happens and the app keeps using
 * plain environment variables (.env), which is what `npm run start:dev`
 * does.
 */

const DEFAULT_SECRET_PATH = 'secret/data/dev-secops/app';

interface AppRoleLoginResponse {
  auth: { client_token: string };
}

interface KvV2ReadResponse {
  data: { data: Record<string, string> };
}

export async function loadSecretsFromVault(
  env: NodeJS.ProcessEnv = process.env,
): Promise<void> {
  const address = env.VAULT_ADDR;
  if (!address) {
    return;
  }

  const roleId = env.VAULT_ROLE_ID;
  const secretId = env.VAULT_SECRET_ID;
  if (!roleId || !secretId) {
    throw new Error(
      'VAULT_ADDR is set but VAULT_ROLE_ID or VAULT_SECRET_ID is missing',
    );
  }

  const token = await login(address, roleId, secretId);
  const secrets = await readSecret(
    address,
    token,
    env.VAULT_SECRET_PATH ?? DEFAULT_SECRET_PATH,
  );

  Object.assign(env, secrets);

  // The secret ID has done its job. Removing it means a later dump of the
  // environment (an error report, a debug endpoint...) cannot leak it.
  delete env.VAULT_SECRET_ID;
}

async function login(
  address: string,
  roleId: string,
  secretId: string,
): Promise<string> {
  const response = await fetch(`${address}/v1/auth/approle/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ role_id: roleId, secret_id: secretId }),
  });
  if (!response.ok) {
    // Never include the request body in the error: it holds the secret ID.
    throw new Error(`Vault login failed with HTTP ${response.status}`);
  }
  const body = (await response.json()) as AppRoleLoginResponse;
  return body.auth.client_token;
}

async function readSecret(
  address: string,
  token: string,
  path: string,
): Promise<Record<string, string>> {
  const response = await fetch(`${address}/v1/${path}`, {
    headers: { 'X-Vault-Token': token },
  });
  if (!response.ok) {
    throw new Error(
      `Reading ${path} from Vault failed with HTTP ${response.status}`,
    );
  }
  const body = (await response.json()) as KvV2ReadResponse;
  return body.data.data;
}
