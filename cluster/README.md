# cluster deployment

this folder contains helm templates for deploying kubernetes clusters via cluster api.

## creating a new cluster

1. **create cluster directory**:
   ```bash
   mkdir cluster/my-new-cluster
   ```

2. **create values.yaml**:
   ```bash
   cp cluster/kube-prd/values.yaml cluster/my-new-cluster/values.yaml
   ```

3. **configure cluster values**:
   - update network settings (vip, ipRange, gateway)
   - adjust node specifications (memory, cores, disk)
   - set proxmox vm id range
   - configure gitops.argocd settings

4. **deploy cluster**:
   ```bash
   helm install my-new-cluster ./templates \
     --values my-new-cluster/values.yaml \
     --set clusterName=my-new-cluster \
     --set targetNamespace=cluster-my-new-cluster \
     --namespace cluster-my-new-cluster \
     --create-namespace
   ```

## cluster configuration

### network
- `network.vip`: virtual ip for control plane
- `network.ipRange`: ip range for capmox to assign to nodes
- `network.gateway`: network gateway

### nodes
```yaml
nodes:
  - type: control-plane
  - type: worker
    memory: 16384  # 16GB
    cores: 4
    disk: 100
```

### gitops
```yaml
gitops:
  argocd:
    enabled: true
    adminPassword: "bcrypt-hashed-password"
    bootstrap:
      enabled: true  # deploys bootstrap application for apps-of-apps
```

### cni
```yaml
cni:
  cilium:
    enabled: true
    version: "1.18.1"
    kubeProxyReplacement: true
```

## automatic deployments

when `gitops.argocd.enabled: true`:
- cluster gets labeled with `argoCDChart: enabled`
- argocd helmchartproxy deploys argocd to the cluster
- if `bootstrap.enabled: true`, bootstrap helmchartproxy deploys bootstrap application

## cluster lifecycle

1. cluster api creates kubernetes cluster
2. caaph deploys argocd via helmchartproxy
3. caaph deploys bootstrap application via helmchartproxy
4. bootstrap application deploys appprojects and applicationsets
5. applicationsets deploy actual workload applications