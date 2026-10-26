import { beforeEach, describe, expect, it, vi } from 'vitest';
import { loadSecretsFromVault } from './vault';

describe('loadSecretsFromVault', () => {
  const fetchMock = vi.fn();

  beforeEach(() => {
    vi.stubGlobal('fetch', fetchMock);
  });

  const jsonResponse = (body: unknown, status = 200) =>
    ({ ok: status < 400, status, json: async () => body }) as Response;

  it('does nothing when VAULT_ADDR is not set', async () => {
    const env: NodeJS.ProcessEnv = { DB_PASSWORD: 'from-env' };

    await loadSecretsFromVault(env);

    expect(fetchMock).not.toHaveBeenCalled();
    expect(env.DB_PASSWORD).toBe('from-env');
  });

  it('logs in with AppRole and copies the secrets into the environment', async () => {
    fetchMock
      .mockResolvedValueOnce(
        jsonResponse({ auth: { client_token: 'token-1' } }),
      )
      .mockResolvedValueOnce(
        jsonResponse({
          data: { data: { DB_PASSWORD: 'from-vault', JWT_SECRET: 'jwt' } },
        }),
      );
    const env: NodeJS.ProcessEnv = {
      VAULT_ADDR: 'http://vault:8200',
      VAULT_ROLE_ID: 'role',
      VAULT_SECRET_ID: 'secret',
    };

    await loadSecretsFromVault(env);

    expect(fetchMock).toHaveBeenLastCalledWith(
      'http://vault:8200/v1/secret/data/dev-secops/app',
      { headers: { 'X-Vault-Token': 'token-1' } },
    );
    expect(env.DB_PASSWORD).toBe('from-vault');
    expect(env.JWT_SECRET).toBe('jwt');
  });

  it('removes the secret ID from the environment after logging in', async () => {
    fetchMock
      .mockResolvedValueOnce(jsonResponse({ auth: { client_token: 't' } }))
      .mockResolvedValueOnce(jsonResponse({ data: { data: {} } }));
    const env: NodeJS.ProcessEnv = {
      VAULT_ADDR: 'http://vault:8200',
      VAULT_ROLE_ID: 'role',
      VAULT_SECRET_ID: 'secret',
    };

    await loadSecretsFromVault(env);

    expect(env.VAULT_SECRET_ID).toBeUndefined();
  });

  it('fails without leaking the secret ID when login is rejected', async () => {
    fetchMock.mockResolvedValueOnce(jsonResponse({}, 403));
    const env: NodeJS.ProcessEnv = {
      VAULT_ADDR: 'http://vault:8200',
      VAULT_ROLE_ID: 'role',
      VAULT_SECRET_ID: 'very-secret-id',
    };

    await expect(loadSecretsFromVault(env)).rejects.toThrow(
      'Vault login failed with HTTP 403',
    );
  });
});
