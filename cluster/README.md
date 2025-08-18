# cluster deployment

this folder contains helm templates for deploying kubernetes clusters via cluster api.

## creating a new cluster

1. **create cluster directory**:

   ```bash
   mkdir cluster/my-new-cluster
   ```
   
   **important**: the directory name becomes the cluster name (e.g., `my-new-cluster` directory creates a cluster named `my-new-cluster`)

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
   git add cluster/my-new-cluster/values.yaml
   git commit -m "add my-new-cluster configuration"
   git push
   ```

   the cluster applicationset will automatically detect the new directory and deploy the cluster via argocd.

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
    memory: 16384 # 16GB
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
      enabled: true # deploys bootstrap application for apps-of-apps
```

### cni

```yaml
cni:
  cilium:
    enabled: true                    # enables cilium cni installation via bootstrap job
    version: "1.18.1"               # cilium version to install
    kubeProxyReplacement: true      # disables kube-proxy and uses cilium's ebpf implementation
```

when `cni.cilium.enabled: true`:
- talos cluster is configured with `cni: none` (disables default flannel/calico)
- kube-proxy is disabled when `kubeProxyReplacement: true` 
- cilium-install job runs during cluster bootstrap to install cilium
- cilium provides cni networking and optionally replaces kube-proxy with ebpf

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
