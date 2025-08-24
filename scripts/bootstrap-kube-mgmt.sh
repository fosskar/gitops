#!/usr/bin/env bash
set -euo pipefail

# Function to run commands with better error reporting
run_cmd() {
  local cmd="$*"
  log_info "running: $cmd"
  if ! $cmd; then
    log_error "command failed: $cmd"
    log_error "check the error output above for details"
    return 1
  fi
}

# configuration
CLUSTER_NAME="kube-mgmt"
CLUSTER_IP="${KUBE_MGMT_IP:-10.10.10.60}" # override with env var if needed
CLUSTER_ENDPOINT="https://${CLUSTER_IP}:6443"
WORK_DIR="$(pwd)/bootstrap-temp"
KUBECONFIG_PATH="$HOME/.kube/config"
TALOSCONFIG_PATH="$HOME/.talos/config"

# colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # no color

log_info() {
  echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
  echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $1"
}

check_prerequisites() {
  log_info "checking prerequisites..."

  for cmd in talosctl kubectl helm; do
    if ! command -v "$cmd" &>/dev/null; then
      log_error "$cmd is required but not installed"
      exit 1
    fi
  done

  log_info "all prerequisites satisfied"
}

validate_existing_configs() {
  # check if we have valid talosconfig that works
  if [ -f "$TALOSCONFIG_PATH" ]; then
    if talosctl version --nodes "$CLUSTER_IP" --endpoints "$CLUSTER_IP" --talosconfig "$TALOSCONFIG_PATH" &>/dev/null; then
      log_info "found working talosconfig"
      return 0  # valid config exists
    else
      log_info "talosconfig exists but certificates don't match node"
      return 1  # invalid config
    fi
  fi
  return 1  # no config
}

check_cluster_exists() {
  log_info "checking if cluster already exists..."

  # check if kubeconfig exists and kubernetes api is responding
  if [ -f "$KUBECONFIG_PATH" ] && KUBECONFIG="$KUBECONFIG_PATH" kubectl cluster-info &>/dev/null; then
    log_info "cluster already exists and kubernetes api is accessible"
    return 0  # true - cluster exists
  fi
  
  # check if talos api is responding with valid config
  if validate_existing_configs; then
    log_info "talos cluster exists with valid configuration"
    return 0  # true - cluster exists with valid config
  fi
  
  return 1  # false - no working cluster found, proceed with bootstrap
}

generate_talos_config() {
  # only generate if we don't have valid configs
  if validate_existing_configs; then
    log_info "using existing valid talos configuration"
    return 0
  fi

  log_info "generating new talos configuration..."

  mkdir -p "$WORK_DIR"
  cd "$WORK_DIR"

  # generate secrets
  if [ ! -f "secrets.yaml" ]; then
    log_info "generating talos secrets..."
    talosctl gen secrets
  else
    log_info "using existing secrets..."
  fi

  # generate configuration
  log_info "generating cluster configuration..."
  talosctl gen config "$CLUSTER_NAME" "$CLUSTER_ENDPOINT" --force

  # modify controlplane.yaml to allow scheduling on control planes
  log_info "modifying controlplane configuration..."
  yq eval '.cluster.allowSchedulingOnControlPlanes = true' -i controlplane.yaml

  cd - >/dev/null
}

wait_for_talos_api() {
  local max_attempts=30
  local attempt=1
  
  log_info "waiting for talos api to be ready..."
  while [ $attempt -le $max_attempts ]; do
    if talosctl version --nodes "$CLUSTER_IP" --endpoints "$CLUSTER_IP" --talosconfig "$WORK_DIR/talosconfig" &>/dev/null; then
      log_info "talos api is ready after ${attempt} attempts"
      return 0
    fi
    log_info "attempt $attempt/$max_attempts - talos api not ready yet, waiting 10 seconds..."
    sleep 10
    ((attempt++))
  done
  
  log_error "talos api failed to become ready after $max_attempts attempts"
  return 1
}

bootstrap_cluster() {
  log_info "applying configuration to talos node..."
  talosctl apply-config --insecure --nodes "$CLUSTER_IP" --file "$WORK_DIR/controlplane.yaml"

  wait_for_talos_api

  log_info "bootstrapping cluster..."
  talosctl bootstrap --nodes "$CLUSTER_IP" --endpoints "$CLUSTER_IP" --talosconfig "$WORK_DIR/talosconfig"

  log_info "waiting for cluster to be ready..."
  talosctl health --nodes "$CLUSTER_IP" --endpoints "$CLUSTER_IP" --talosconfig "$WORK_DIR/talosconfig" --wait-timeout=10m

  log_info "retrieving kubeconfig..."
  mkdir -p "$(dirname "$KUBECONFIG_PATH")"
  talosctl kubeconfig --nodes "$CLUSTER_IP" --endpoints "$CLUSTER_IP" --talosconfig "$WORK_DIR/talosconfig" --merge=true "$KUBECONFIG_PATH"

  log_info "waiting for kubernetes api to be ready..."
  kubectl wait --for=condition=Ready nodes --all --timeout=600s

  # save configs only after complete successful bootstrap
  save_configs
}

install_argocd() {
  log_info "installing argocd..."

  # create argocd namespace
  log_info "creating argocd namespace..."
  kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

  # install argocd using helm
  log_info "adding helm repository..."
  helm repo add argo https://argoproj.github.io/argo-helm
  helm repo update

  log_info "installing argocd via helm (this may take several minutes)..."
  if ! helm upgrade --install argocd argo/argo-cd \
    --namespace argocd \
    --set server.service.type=NodePort \
    --set server.service.nodePortHttp=30080 \
    --set server.service.nodePortHttps=30443 \
    --wait --timeout=10m; then
    log_error "argocd installation failed"
    log_error "you can check the status with: kubectl get pods -n argocd"
    return 1
  fi

  log_info "waiting for argocd to be ready..."
  kubectl wait --for=condition=Available deployment/argocd-server -n argocd --timeout=300s
}

apply_bootstrap_application() {
  log_info "creating bootstrap application to connect argocd to gitops repo..."

  kubectl apply -f - <<EOF
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: bootstrap
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io/background
spec:
  project: default
  source:
    repoURL: https://codeberg.org/smonoscr/gitops.git
    targetRevision: main
    path: bootstrap/kube-mgmt
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF

  log_info "bootstrap application created - argocd will now manage cluster api and other components"
}

configure_argocd() {
  log_info "configuring argocd settings..."
  
  # set admin password to "admin123" (bcrypt hash)
  local admin_password_hash='$2y$05$eGUGWXy6S8F3i3XbEu/Z9.PxIww7OCRk4eSN0IgOiDlLenqzw3Aum'
  
  kubectl patch secret argocd-secret -n argocd -p="{\"data\":{\"admin.password\":\"$(echo -n "$admin_password_hash" | base64 -w 0)\"}}"
  
  log_info "argocd admin password set to 'admin123'"
}

cleanup_temp_files() {
  log_info "cleaning up temporary files..."
  rm -rf "$WORK_DIR"
}

cleanup_on_error() {
  local exit_code=$?
  log_error "script failed with exit code $exit_code"
  log_error "preserving config files in $WORK_DIR for debugging"
  log_info "you can manually continue with:"
  log_info "  talosctl bootstrap --nodes $CLUSTER_IP --endpoints $CLUSTER_IP --talosconfig $WORK_DIR/talosconfig"
  exit $exit_code
}

save_configs() {
  log_info "merging configuration files..."

  # ensure talos config directory exists
  mkdir -p "$(dirname "$TALOSCONFIG_PATH")"
  
  # merge talosconfig
  if [ -f "$TALOSCONFIG_PATH" ]; then
    # check if only one context exists and it's our cluster
    context_count=$(talosctl config contexts --talosconfig "$TALOSCONFIG_PATH" 2>/dev/null | wc -l || echo "0")
    if [ "$context_count" -eq 1 ] && talosctl config contexts --talosconfig "$TALOSCONFIG_PATH" 2>/dev/null | grep -q "^$CLUSTER_NAME"; then
      log_info "replacing single context talosconfig"
      cp "$WORK_DIR/talosconfig" "$TALOSCONFIG_PATH"
    else
      log_info "merging talosconfig with existing configuration"
      talosctl config remove "$CLUSTER_NAME" --talosconfig "$TALOSCONFIG_PATH" 2>/dev/null || true
      talosctl config merge "$WORK_DIR/talosconfig"
    fi
  else
    log_info "creating new talosconfig"
    cp "$WORK_DIR/talosconfig" "$TALOSCONFIG_PATH"
  fi

  # set endpoint for the merged context
  log_info "configuring talos endpoint..."
  talosctl config endpoint "$CLUSTER_IP" --talosconfig "$TALOSCONFIG_PATH"
  
  log_info "configuration files saved:"
  log_info "  kubeconfig: $KUBECONFIG_PATH" 
  log_info "  talosconfig: $TALOSCONFIG_PATH"
  log_info "  endpoint configured: $CLUSTER_IP"
}

main() {
  log_info "starting bootstrap of $CLUSTER_NAME cluster..."
  log_info "cluster ip: $CLUSTER_IP"
  log_info "cluster endpoint: $CLUSTER_ENDPOINT"

  # set kubeconfig environment variable to avoid --kubeconfig flags
  export KUBECONFIG="$KUBECONFIG_PATH"
  log_info "using kubeconfig: $KUBECONFIG"

  check_prerequisites
  
  if check_cluster_exists; then
    log_info "cluster already exists, skipping bootstrap..."
    
    # ensure we have kubeconfig for existing cluster
    if [ ! -f "$KUBECONFIG_PATH" ]; then
      log_info "retrieving kubeconfig for existing cluster..."
      mkdir -p "$(dirname "$KUBECONFIG_PATH")"
      if ! talosctl kubeconfig --nodes "$CLUSTER_IP" --endpoints "$CLUSTER_IP" --talosconfig "$TALOSCONFIG_PATH" --merge=true "$KUBECONFIG_PATH" 2>/dev/null; then
        log_warn "failed to get kubeconfig with saved talosconfig, certificates may be mismatched"
        log_error "please reset the talos node and try again:"
        log_error "  talosctl reset --nodes $CLUSTER_IP --endpoints $CLUSTER_IP --insecure"
        exit 1
      fi
    fi
    
    install_argocd
    apply_bootstrap_application
    configure_argocd
  else
    generate_talos_config
    bootstrap_cluster
    install_argocd
    apply_bootstrap_application
    configure_argocd
  fi
  
  cleanup_temp_files

  log_info "bootstrap completed successfully!"
  log_info ""
  log_info "next steps:"
  log_info "  1. access argocd at: http://$CLUSTER_IP:30080"
  log_info "  2. login with username: admin, password: admin123"
  log_info "  3. use kubeconfig: export KUBECONFIG=$KUBECONFIG_PATH"
  log_info "  4. check cluster status: kubectl get nodes"
  log_info "  5. monitor cluster api deployment: kubectl get applications -n argocd"
}

# trap cleanup on error, preserve files for debugging
trap cleanup_on_error ERR

main "$@"
