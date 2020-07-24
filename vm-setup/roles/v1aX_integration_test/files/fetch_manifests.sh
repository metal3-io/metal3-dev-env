#!/bin/bash

mkdir -p /tmp/manifests

manifests=(
  bmh
  cluster
  deployment
  machine
  machinedeployment
  machinehealthchecks
  machinesets
  machinepools
  m3cluster
  m3machine
  metal3machinetemplate
  kcp
  kubeadmconfig
  kubeadmconfigtemplates
  kubeadmcontrolplane
  replicaset
)

if [[ "${CAPI_VERSION}" == "v1alpha4" ]]; then 
   manifests+=("ippool" "ipclaim" "ipaddress" "m3data" "m3dataclaim" "m3datatemplate") 
fi

for kind in "${manifests[@]}"; do
  mkdir -p /tmp/manifests/"$kind"
  for name in $(kubectl get -n metal3 -o name "$kind" || true)
  do
    kubectl get -n metal3 -o yaml "$name" > /tmp/manifests/"$kind"/"$(basename "$name")".yaml || true
  done
done