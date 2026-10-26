# What the API is allowed to do in Vault: read its own secret. Nothing
# else. No listing other paths, no writing, no managing Vault.
path "secret/data/dev-secops/app" {
  capabilities = ["read"]
}
