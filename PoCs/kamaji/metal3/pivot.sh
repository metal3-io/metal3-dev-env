#!/usr/bin/env bash

set -eux

# Label CRDs to include in move
kubectl label crd baremetalhosts.metal3.io clusterctl.cluster.x-k8s.io=""
kubectl label crd baremetalhosts.metal3.io cluster.x-k8s.io/move=""
kubectl label crd hardwaredata.metal3.io clusterctl.cluster.x-k8s.io=""
kubectl label crd hardwaredata.metal3.io clusterctl.cluster.x-k8s.io/move=""

# Wait for the management cluster to be available
kubectl wait --for=condition=Ready --timeout=300s cluster/test-1

clusterctl get kubeconfig test-1 > kubeconfig.yaml

clusterctl --kubeconfig=kubeconfig.yaml init --control-plane kubeadm --infrastructure metal3
curl -Ls https://github.com/metal3-io/ip-address-manager/releases/latest/download/ipam-components.yaml |
  clusterctl generate yaml | kubectl apply -f -

kubectl --kubeconfig=kubeconfig.yaml apply -k metal3/bmo-management
kubectl --kubeconfig=kubeconfig.yaml apply -k metal3/ironic-management
echo "Waiting for Ironic to be available..."
kubectl --kubeconfig=kubeconfig.yaml wait --for=condition=Available --timeout=300s \
  deployment/ironic -n baremetal-operator-system
echo "Ironic is available."

# Move the cluster. This will also move the BMHs and hardwaredata that are part of the cluster.
clusterctl move --to-kubeconfig=kubeconfig.yaml

# Manually move BMHs that are not part of the cluster
mkdir -p metal3/tmp/bmhs
for bmh in $(kubectl get bmh -o jsonpath="{.items[*].metadata.name}"); do
  echo "Saving BMH ${bmh}..."
  # Save the BMH status
  # Remove status.hardware since this is part of the hardwaredata
  kubectl get bmh "${bmh}" -o jsonpath="{.status}" |
    jq 'del(.hardware)' > "metal3/tmp/bmhs/${bmh}-status.json"
  # Save the BMH with the status annotation
  kubectl annotate bmh "${bmh}" \
    baremetalhost.metal3.io/status="$(cat "metal3/tmp/bmhs/${bmh}-status.json")" \
    --dry-run=client -o yaml > "metal3/tmp/bmhs/${bmh}-bmh.yaml"
  # Save the hardwaredata
  kubectl get hardwaredata "${bmh}" -o yaml > "metal3/tmp/bmhs/${bmh}-hardwaredata.yaml"
  # Save the BMC credentials
  secret="$(kubectl get bmh "${bmh}" -o jsonpath="{.spec.bmc.credentialsName}")"
  kubectl get secret "${secret}" -o yaml > "metal3/tmp/bmhs/${bmh}-bmc-secret.yaml"

  # Detach BMHs
  kubectl annotate bmh "${bmh}" baremetalhost.metal3.io/detached="manual-move"
  # Cleanup
  rm "metal3/tmp/bmhs/${bmh}-status.json"
done

# Apply the BMHs and hardwaredata in the management cluster
kubectl --kubeconfig=kubeconfig.yaml apply -f metal3/tmp/bmhs

# Cleanup
# Check that BMHs have operational status detatched
kubectl wait bmh --all --for=jsonpath="{.status.operationalStatus}"=detached
kubectl delete bmh --all
rm -r metal3/tmp/bmhs
