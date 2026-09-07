# k8s/ingress/cert-manager

cert-manager configuration for the platform. cert-manager issues TLS certificates
from Let's Encrypt using DNS-01 challenges.

## What is configured here

- ClusterIssuer for Let's Encrypt production.
- DNS-01 challenge configuration (Cloudflare API token).

## What is not configured here

- Certificate resources. That is the Ingress resource's job (via annotations).
- DNS records. That is Terraform's job (terraform/modules/tenant).
