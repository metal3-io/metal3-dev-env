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
REL_PATH_TO_DEV_ENV=$(realpath --relative-to="${BMOPATH}" "${SCRIPTDIR}")
sed -i "s|yaml = str(kustomizesub(context + \"/config\"))|yaml = str(kustomizesub(\"${REL_PATH_TO_DEV_ENV}/config/overlays/tilt\"))|" Tiltfile
make kind-reset
kind create cluster --name capm3 --image="${KIND_NODE_IMAGE}"
kubectl create namespace "${NAMESPACE}"
kubectl create namespace "${IRONIC_NAMESPACE}"
patch_clusterctl
make tilt-up &
# wait for cert-manager to be ready, timeout after 120 seconds
for i in {1..8}; do
    kubectl get pods -n cert-manager | grep -E 'webhook.*Running' && break
    echo "Waiting for cert-manager webhooks to be ready... Attempt $i/8"
    sleep 15
done
launch_ironic
# deploy bmo in order to generate ironic credentials and tls
launch_baremetal_operator
apply_bm_hosts "${NAMESPACE}"
# remove bmo, so that is deployed and monitored by Tilt
kubectl delete deployments.apps -n "${IRONIC_NAMESPACE}" baremetal-operator-controller-manager

# shellcheck disable=SC2155
# shellcheck disable=SC1001
export IRONIC_SECRET_NAME=$(kubectl get secrets  -n "${IRONIC_NAMESPACE}" -oname | grep ironic-credentials | cut -f2 -d\/)
# shellcheck disable=SC2155
# shellcheck disable=SC1001
export IRONICINSPECTOR_SECRET_NAME=$(kubectl get secrets  -n "${IRONIC_NAMESPACE}" -oname | grep "ironic-inspector-credentials" | cut -f2 -d\/)
popd

pushd "${SCRIPTDIR}"
# Relative path from SCRIPTDIR to BMOPATH
REL_PATH_TO_BMO="$(realpath --relative-to="${SCRIPTDIR}" "${BMOPATH}")"

# Create overlay
mkdir -p config/overlays/tilt/
cat <<EOF > config/overlays/tilt/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
- ../../../${REL_PATH_TO_BMO}/config/namespace
- ../../../${REL_PATH_TO_BMO}/config/default

components:
- ../../../${REL_PATH_TO_BMO}/config/components/tls

patches:
- path: ironic-credentials-patch.yaml
EOF

# use existing ironic and inspector secrets
# Tilt cannot generate new credentials and certificates as it would mismatch with what ironic is already configured with
cat <<EOF > config/overlays/tilt/ironic-credentials-patch.yaml
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
EOF

if [[ -n "${IRONICINSPECTOR_SECRET_NAME}" ]]; then
    cat <<EOF >> config/overlays/tilt/ironic-credentials-patch.yaml
          - mountPath: /opt/metal3/auth/ironic-inspector
            name: ironic-inspector-credentials
            readOnly: true
      volumes:
      - name: ironic-credentials
        secret:
          secretName: ${IRONIC_SECRET_NAME}
      - name: ironic-inspector-credentials
        secret:
          secretName: ${IRONICINSPECTOR_SECRET_NAME}
EOF
else
    cat <<EOF >> config/overlays/tilt/ironic-credentials-patch.yaml
      volumes:
      - name: ironic-credentials
        secret:
          secretName: ${IRONIC_SECRET_NAME}
EOF
fi

"${BMOPATH}"/tools/bin/kustomize build config/overlays/tilt
popd

pushd "${CAPM3PATH}"
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
