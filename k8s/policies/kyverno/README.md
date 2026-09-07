# k8s/policies/kyverno

Kyverno policies for the platform. Kyverno is a policy engine that validates,
mutates, and generates Kubernetes resources.

## Policies

- `require-labels.yaml`: Require that every namespace has the Pod Security Standard
  labels. A namespace created by a new ApplicationSet cannot arrive unlabelled.

## What is not enforced here

- Pod Security Standards. That is the namespace labels' job (enforced by the
  Kubernetes API server).
- Network policies. That is the NetworkPolicy's job.
- Resource limits. That is a separate Kyverno policy (not yet written).
