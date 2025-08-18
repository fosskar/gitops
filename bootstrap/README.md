# bootstrap configuration

this folder contains cluster-specific bootstrap configurations for the apps-of-apps pattern.

## structure

```
bootstrap/
├── kube-mgmt/          # management cluster bootstrap
│   ├── cluster_proj.yaml
│   └── clusters.yaml
└── kube-prd/           # workload cluster bootstrap  
    ├── infra_proj.yaml
    └── infra_apps.yaml
```

## creating bootstrap for new cluster

1. **create cluster directory**:
   ```bash
   mkdir bootstrap/my-new-cluster
   ```
   
   **important**: the directory name must match the cluster name from `cluster/` folder

2. **copy base files**:
   ```bash
   cp bootstrap/kube-prd/infra_proj.yaml bootstrap/my-new-cluster/
   cp bootstrap/kube-prd/infra_apps.yaml bootstrap/my-new-cluster/
   ```

3. **configure infra applications**:
   edit `infra_apps.yaml` to specify which applications to deploy:
   ```yaml
   # example: only deploy cert-manager and ingress
   directories:
     - path: infra/cert-manager
     - path: infra/ingress-controller
   ```

4. **enable bootstrap in cluster values**:
   ```yaml
   # cluster/my-new-cluster/values.yaml
   gitops:
     argocd:
       bootstrap:
         enabled: true
   ```

## how bootstrap works

1. **cluster deployment**: cluster api deploys cluster with argocd
2. **bootstrap trigger**: bootstrap helmchartproxy deploys bootstrap application
3. **bootstrap deploys**: appproject and applicationset from `bootstrap/{clusterName}/`
4. **apps deployment**: applicationset deploys applications from `infra/*`

## cluster types

### management clusters (kube-mgmt)
- include cluster management capabilities
- deploy `cluster_proj.yaml` and `clusters.yaml`
- manage other clusters via cluster api

### workload clusters (kube-prd, etc)
- include only infra applications
- deploy `infra_proj.yaml` and `infra_apps.yaml`
- no cluster management capabilities

## customization

each cluster can have different infra applications by:
- customizing the applicationset generators in `infra_apps.yaml`
- creating cluster-specific application configurations
- using values overrides in applicationset templates