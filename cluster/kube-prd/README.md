# kube-prd cluster

production kubernetes cluster running on proxmox with talos linux.

## network configuration

### physical network
- **network**: `10.10.10.0/24`
- **gateway**: `10.10.10.1`
- **vip (control plane)**: `10.10.10.10`

### cluster nodes
- **ip range**: `10.10.10.101-110` (assigned by capmox)
- **control plane**: 1 node
- **workers**: 3 nodes (16gb ram, 4 cores each)

### cilium load balancer
- **loadbalancer ip pool**: `10.10.10.120-183` (`/26` = 64 ips)
- **purpose**: external ips for LoadBalancer services
- **announced via**: l2 arp announcements

## cluster features

- **os**: talos linux (immutable)
- **cni**: cilium with wireguard encryption
- **kube-proxy**: replaced by cilium ebpf
- **routing**: direct node routes (same l2 network)
- **ingress**: gateway api (via cilium envoy)
- **gitops**: argocd with bootstrap apps-of-apps pattern

## deployment

cluster is deployed via cluster api (capmox provider) from the management cluster.
configuration changes are made by updating `values.yaml` and committing to git.