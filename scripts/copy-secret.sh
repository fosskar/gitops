#!/bin/bash

# Simple script to copy proxmox-credentials secret to cluster namespaces
SOURCE_NAMESPACE="default"
SECRET_NAME="proxmox-credentials"

# Get list of cluster namespaces
CLUSTER_NAMESPACES=$(kubectl get namespaces -o name | grep "cluster-" | cut -d'/' -f2)

for ns in $CLUSTER_NAMESPACES; do
  echo "copying secret to namespace: $ns"
  kubectl get secret $SECRET_NAME -n $SOURCE_NAMESPACE -o yaml | \
    sed "s/namespace: $SOURCE_NAMESPACE/namespace: $ns/" | \
    kubectl apply -f -
done

echo "secret distribution complete"