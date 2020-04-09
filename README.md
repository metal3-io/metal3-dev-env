# Metal³ Development Environment

This repository includes scripts to set up a Metal³ development environment.

## Build Status

[![Ubuntu V1alpha3 build status](https://jenkins.nordix.org/view/Airship/job/airship_master_v1a3_integration_test_ubuntu/badge/icon?subject=Ubuntu%20E2E%20V1alpha3)](https://jenkins.nordix.org/view/Airship/job/airship_master_v1a3_integration_test_ubuntu)
[![CentOS V1alpha3 build status](https://jenkins.nordix.org/view/Airship/job/airship_master_v1a3_integration_test_centos/badge/icon?subject=CentOS%20E2E%20V1alpha3)](https://jenkins.nordix.org/view/Airship/job/airship_master_v1a3_integration_test_centos)
[![Ubuntu V1alpha4 build status](https://jenkins.nordix.org/view/Airship/job/airship_master_v1a4_integration_test_ubuntu/badge/icon?subject=Ubuntu%20E2E%20V1alpha4)](https://jenkins.nordix.org/view/Airship/job/airship_master_v1a4_integration_test_ubuntu)
[![CentOS V1alpha4 build status](https://jenkins.nordix.org/view/Airship/job/airship_master_v1a4_integration_test_centos/badge/icon?subject=CentOS%20E2E%20V1alpha4)](https://jenkins.nordix.org/view/Airship/job/airship_master_v1a4_integration_test_centos)

## Instructions

Instructions can be found here: <https://metal3.io/try-it.html>

## Quickstart

Versions v1alpha3 or v1alpha4 are later referred as **v1alphaX**.

The v1alphaX deployment can be done with Ubuntu 18.04 or Centos 8 target host
images.

### Requirements

#### Dev env size

The requirements for the dev env machine are, when deploying **Ubuntu** target
hosts:

* 16GB of memory
* 4 cpus

And when deploying **Centos** target hosts:

* 32GB of memory
* 4 cpus

The Minikube machine is deployed with 4GB of RAM, and 2 vCPUs, and the target
hosts with 4 vCPUs and either 4GB of RAM (Ubuntu) or 8GB of RAM (Centos).

### Environment variables

Select:

```sh
export CAPI_VERSION=v1alpha3
```

or

```sh
export CAPI_VERSION=v1alpha4
```

The following environment variables need to be set for **Centos**:

```sh
export IMAGE_OS=Centos
export DEFAULT_HOSTS_MEMORY=8192
```

And the following environment variables need to be set for **Ubuntu**:

```sh
export IMAGE_OS=Ubuntu
export DEFAULT_HOSTS_MEMORY=4096
```

### Deploy the metal3 Dev env

```sh
./01_prepare_host.sh
./02_configure_host.sh
./03_launch_mgmt_cluster.sh
```

### Deploy the target cluster

```sh
./scripts/v1alphaX/provision_cluster.sh
./scripts/v1alphaX/provision_controlplane.sh
./scripts/v1alphaX/provision_worker.sh
```

### Delete the target cluster

```sh
kubectl delete cluster "${CLUSTER_NAME:-"test1"}" -n metal3
```
