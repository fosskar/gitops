# gitops

Flux-managed GitOps repository for the Talos playground cluster (`kube-nixbox`).

Helm-first: applications are packaged as Helm charts and deployed via
`HelmRelease`. Flux `Kustomization` objects are only the delivery mechanism —
no kustomize overlays or patches unless a chart can't express something
(then use `spec.postRenderers` on the HelmRelease).

## Layout

```
clusters/
  kube-nixbox/
    flux-system/      # Flux's own manifests, owned by `flux bootstrap` — do not edit
    apps.yaml         # Flux Kustomization: applies ./apps, prunes deletions
apps/
  kustomization.yaml  # lists the app directories to deploy
  <app>/              # one directory per application
    repo.yaml         # HelmRepository (chart source)
    release.yaml      # HelmRelease (chart, values, targetNamespace)
```

## Adding an application

1. Create `apps/<app>/` with `repo.yaml` (HelmRepository) and `release.yaml`
   (HelmRelease). Set `spec.targetNamespace` and `spec.install.createNamespace: true`
   in the HelmRelease — no separate Namespace manifests needed.
2. Add `- <app>` to `resources` in `apps/kustomization.yaml`.
3. Commit and push. Flux reconciles within the Kustomization interval, or force it:

   ```
   flux reconcile kustomization apps --with-source
   ```

Removing an application: delete its directory and resource entry, push —
`prune: true` removes it from the cluster.

## Cluster access

Cluster and VM are managed in [nixfiles](https://github.com/fosskar/nixfiles)
(`modules/nixos/virtualization/talos-vm.nix`). APIs: `kube-nixbox.nx3.eu:16443`
(kubernetes), `kube-nixbox.nx3.eu:50000` (talos).
