# ansible/roles/keycloak

Install and configure Keycloak on a host declared by `terraform/modules/keycloak-vm`.

The role reads `/etc/viavitae/keycloak-hostname` to determine the public hostname and
refuses to run if the file is absent. The hostname is what Keycloak uses in the issuer
field of tokens and in the discovery document; it must match the hostname the application
uses, and a mismatch breaks OIDC validation.

Keycloak connects to the tenant PostgreSQL instance (the same one the application uses)
for its own data. The connection parameters come from the inventory; the password comes
from `vault.sops.yml`.

## What the role does not do

- It does not create realms, clients or users. That is done via the Keycloak admin
  console or the Terraform Keycloak provider.
- It does not configure TLS termination. That is the reverse proxy's job (Traefik in
  the cluster, or HAProxy on the LBs).
- It does not configure MFA. That is done via the Keycloak admin console.
