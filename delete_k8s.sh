#!/bin/bash
set -xe
source lib/logging.sh
source lib/common.sh

if [ $K8S == "minikube" ];then
  minikube delete
else
  kinder="${GOPATH}/bin/kinder"
  if [[ $(sudo $kinder get clusters) == "kind"  ]]; then
     sudo $kinder delete cluster
  fi
fi
