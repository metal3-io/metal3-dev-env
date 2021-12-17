#!/bin/bash

set -xe

echo "Deploy tilt environment"

pushd "${BMOPATH}"
# Required to deploy BMO as part of the tilt environment
sed -i 's/"kustomize_config":.*/"kustomize_config": true,/' tilt-provider.json
popd

pushd "${CAPM3PATH}"
cat <<EOF > tilt-settings.json
{
  "provider_repos": ["../ip-address-manager"],
  "enable_providers": ["metal3-ipam"],
  "kustomize_substitutions": {
      "DEPLOY_KERNEL_URL": "${DEPLOY_KERNEL_URL}",
      "DEPLOY_RAMDISK_URL": "${DEPLOY_RAMDISK_URL}",
      "IRONIC_INSPECTOR_URL": "${IRONIC_INSPECTOR_URL}",
      "IRONIC_URL": "${IRONIC_URL}"
  }
}
EOF
sed -i 's/yaml = str(kustomizesub(context + "\/config"))/yaml = str(kustomizesub(context + "\/config\/tls"))/' Tiltfile
make kind-reset
kind create cluster --name capm3 --image="kindest/node:${KIND_NODE_IMAGE_VERSION}"
kubectl create namespace "${NAMESPACE}"
kubectl create namespace "${IRONIC_NAMESPACE}"
mkdir -p "${HOME}/.cluster-api/overrides/infrastructure-metal3/${CAPM3RELEASE}"
make tilt-up &
# wait for cert-manager to be ready
sleep 120
launch_ironic
# deploy bmo in order to generate ironic credentials and tls
launch_baremetal_operator
apply_bm_hosts
# remove bmo, so that is deployed and monitored by Tilt
kubectl delete deployments.apps -n "${IRONIC_NAMESPACE}" baremetal-operator-controller-manager

pushd "${BMOPATH}"
# shellcheck disable=SC2155
# shellcheck disable=SC1001
export IRONIC_SECRET_NAME=$(kubectl get secrets  -n "${IRONIC_NAMESPACE}" -oname | grep ironic-credentials | cut -f2 -d\/)
# shellcheck disable=SC2155
# shellcheck disable=SC1001
export IRONICINSPECTOR_SECRET_NAME=$(kubectl get secrets  -n "${IRONIC_NAMESPACE}" -oname | grep "ironic-inspector-credentials" | cut -f2 -d\/)

# use existing ironic and inspector secrets 
# Tilt cannot generate new credentials and certificates as it would mismatch with what ironic is already configured with
cat <<EOF >> config/tls/tls_ca_patch.yaml

---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: controller-manager
  namespace: system
spec:
  template:
    spec:
      containers:
      - name: manager
        volumeMounts:
          - mountPath: /opt/metal3/auth/ironic
            name: ironic-credentials
            readOnly: true
          - mountPath: /opt/metal3/auth/ironic-inspector
            name: ironic-inspector-credentials
            readOnly: true
      volumes:  
      - name: ironic-credentials
        secret:
          secretName: ${IRONICINSPECTOR_SECRET_NAME}
      - name: ironic-inspector-credentials
        secret: 
          secretName: ${IRONIC_SECRET_NAME}
EOF
tools/bin/kustomize build config/tls/
popd

# Start watching changes on bmo
cat <<EOF > tilt-settings.json
{
  "provider_repos": [ "../baremetal-operator", "../ip-address-manager"],
  "enable_providers": [ "metal3-bmo", "metal3-ipam"],
  "kustomize_substitutions": {
      "DEPLOY_KERNEL_URL": "${DEPLOY_KERNEL_URL}",
      "DEPLOY_RAMDISK_URL": "${DEPLOY_RAMDISK_URL}",
      "IRONIC_INSPECTOR_URL": "${IRONIC_INSPECTOR_URL}",
      "IRONIC_URL": "${IRONIC_URL}"
  }
}
EOF
popd

