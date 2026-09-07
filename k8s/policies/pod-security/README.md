# k8s/policies/pod-security

Pod Security Standards are enforced at the namespace level via labels (see
`k8s/namespaces/`). This directory contains supplementary policies that enforce
additional constraints beyond the Pod Security Standards.

## What is enforced

- `restricted` on every namespace except `ingress` and `cert-manager`.
- `privileged` on `ingress` and `cert-manager`, which require privileged access
  for their function.

## What is not enforced here

- Resource limits. That is the Kyverno policy's job.
- Image pull secrets. That is the ApplicationSet's job.
- Service account tokens. That is the RBAC policy's job.
