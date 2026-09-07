# Argo CD Bootstrap

This directory documents the manual bootstrap step that precedes all GitOps-managed
resources. Everything under `k8s/` is pulled by Argo CD after this step; nothing
before it can be automated without a running cluster.

## Prerequisites

- A running K3s cluster (bootstrapped by `ansible/playbooks/k3s-bootstrap.yml` and
  `k3s-nodes.yml`).
- Argo CD installed in the `argocd` namespace. Use the official manifest or Helm chart:

  ```bash
  kubectl create namespace argocd
  kubectl apply -n argocd -f \
    https://raw.githubusercontent.com/argoproj/argo-cd/v2.14.6/manifests/install.yaml
  ```

- The `k8s/namespaces/` manifests applied so that `api`, `web`, `ingress`,
  `cert-manager` and `monitoring` namespaces exist before Argo CD syncs them.

## Bootstrap

Apply the root application once:

```bash
kubectl apply -f k8s/argocd/root-app.yaml
```

This creates the `viavitae-root` Application, which points at `k8s/argocd/` in this
repository with `recurse: true`. Argo CD then discovers and syncs:

- `projects/platform.yaml` — the AppProject that scopes what the ApplicationSet may do.
- `applicationsets/platform.yaml` — the matrix generator that creates per-environment,
  per-component Applications for `k8s/platform/{env}/{component}`.

After the root app syncs, every subsequent change to `k8s/` is pulled automatically.
No further manual `kubectl apply` is needed for normal operations.

## Recovery

If the root app is misconfigured (wrong `repoURL`, broken `path`, deleted out-of-band),
Argo CD can no longer self-heal. Recovery:

1. **Diagnose.** Check whether the root app exists and what state it reports:

   ```bash
   kubectl -n argocd get application viavitae-root -o yaml
   argocd app get viavitae-root
   ```

2. **Fix the manifest.** Edit `k8s/argocd/root-app.yaml` in this repository and merge
   the fix to `main`. The root app reads from `main`, so a merged fix is what Argo CD
   will reconcile once it can sync again.

3. **Re-apply the corrected manifest:**

   ```bash
   kubectl apply -f k8s/argocd/root-app.yaml
   ```

4. **Force a sync if the automated policy is stuck:**

   ```bash
   argocd app sync viavitae-root --prune
   ```

5. **If the Argo CD namespace itself is damaged** (e.g. someone deleted the `argocd`
   namespace), reinstall Argo CD from the manifest above, re-apply the namespaces from
   `k8s/namespaces/`, then re-apply `root-app.yaml`. The ApplicationSet will recreate
   all child Applications on the next sync cycle.

## What is NOT managed by Argo CD

- Argo CD itself (installed from an upstream manifest, not from this repository).
- `cert-manager` CRDs (installed by the Ansible `k3s-nodes` role before Argo CD runs).
- Cluster-wide resources that require imperative setup (e.g. the ClusterSecretStore
  identity binding, which depends on the external-secrets operator being installed first).
