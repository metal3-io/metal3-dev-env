#!/usr/bin/env bash

set -eux

clusterctl init --kubeconfig="${KUBECONFIG}" --control-plane kamaji:v0.15.2
# Install metallb (needed for Kamaji k8s API endpoints)
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.15.2/config/manifests/metallb-native.yaml
kubectl -n metallb-system wait --for=condition=Available deployment/controller
# Create an IPAddressPool and L2Advertisement
kubectl apply -k metallb
# Install local-path-provisioner (needed for Kamaji etcd)
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.31/deploy/local-path-storage.yaml
kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

# Install kamaji
helm repo add clastix https://clastix.github.io/charts
helm repo update
helm upgrade kamaji clastix/kamaji \
  --install \
  --version 0.0.0+latest \
  --namespace kamaji-system \
  --create-namespace \
  --set image.tag=latest

kubectl apply -k setup-scripts

# Create the workload cluster with Kamaji as control-plane provider
kubectl apply -k kamaji

# There seems to be a bug in the Kamaji control-plane provider that prevents the
# kamajicontrolplane from becoming ready sometimes.
# This is a workaround to trigger a reconciliation that makes it ready.
replicas=1
for i in {1..5}; do
    if [[ "$(kubectl get kamajicontrolplane kamaji-1 -o jsonpath='{.status.ready}')" = "true" ]]; then
        break
    fi
    replicas=$((3 - replicas))  # Toggle between 1 and 2
    echo "Attempt $i: KamajiControlPlane not ready. Scaling to ${replicas} replicas..."
    kubectl scale --replicas=${replicas} kamajicontrolplane kamaji-1
    sleep 2
done
