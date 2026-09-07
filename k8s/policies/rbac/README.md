# k8s/policies/rbac

RBAC policies for the platform. The policies in this directory grant the minimum
privileges required for each component to function.

## Principles

1. No workload runs as `cluster-admin`. A workload that needs cluster-wide access
   is a workload whose scope is too broad.
2. Service accounts are per-namespace. A service account that is shared across
   namespaces is a service account whose privileges are too broad.
3. Roles are per-namespace. ClusterRoles are used only for cluster-wide resources
   (namespaces, CRDs).

## What is not enforced here

- Pod Security Standards. That is the namespace labels' job.
- Network policies. That is the NetworkPolicy's job.
- Resource limits. That is the Kyverno policy's job.
