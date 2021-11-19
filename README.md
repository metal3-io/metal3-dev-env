# Metal³ Development Environment

This repository includes scripts to set up a Metal³ development environment.

## Build Status

[![Ubuntu V1alpha4 build status](https://jenkins.nordix.org/view/Airship/job/airship_master_v1a4_integration_test_ubuntu/badge/icon?subject=Ubuntu%20E2E%20V1alpha4)](https://jenkins.nordix.org/view/Airship/job/airship_master_v1a4_integration_test_ubuntu)
[![CentOS V1alpha4 build status](https://jenkins.nordix.org/view/Airship/job/airship_master_v1a4_integration_test_centos/badge/icon?subject=CentOS%20E2E%20V1alpha4)](https://jenkins.nordix.org/view/Airship/job/airship_master_v1a4_integration_test_centos)
[![Ubuntu V1alpha5 build status](https://jenkins.nordix.org/view/Airship/job/airship_master_v1a5_integration_test_ubuntu/badge/icon?subject=Ubuntu%20E2E%20V1alpha5)](https://jenkins.nordix.org/view/Airship/job/airship_master_v1a5_integration_test_ubuntu)
[![CentOS V1alpha5 build status](https://jenkins.nordix.org/view/Airship/job/airship_master_v1a5_integration_test_centos/badge/icon?subject=CentOS%20E2E%20V1alpha5)](https://jenkins.nordix.org/view/Airship/job/airship_master_v1a5_integration_test_centos)
[![Ubuntu V1beta1 build status](https://jenkins.nordix.org/view/Airship/job/airship_master_v1b1_integration_test_ubuntu/badge/icon?subject=Ubuntu%20E2E%20V1beta1)](https://jenkins.nordix.org/view/Airship/job/airship_master_v1b1_integration_test_ubuntu)
[![CentOS V1beta1 build status](https://jenkins.nordix.org/view/Airship/job/airship_master_v1b1_integration_test_centos/badge/icon?subject=CentOS%20E2E%20V1beta1)](https://jenkins.nordix.org/view/Airship/job/airship_master_v1b1_integration_test_centos)

## Instructions

Instructions can be found here: <https://metal3.io/try-it.html>

## Quickstart

Versions v1alpha4, v1alpha5 or v1beta1 are later referred as **v1alphaX**/**v1betaX**.

The v1alphaX or v1betaX deployment can be done with Ubuntu 18.04, 20.04 or
Centos 8 Stream target host images. By default, for Ubuntu based target hosts
we are using Ubuntu 20.04

### Requirements

#### Dev env size

The requirements for the dev env machine are, when deploying **Ubuntu** target
hosts:

* 8GB of memory
* 4 cpus

And when deploying **Centos** target hosts:

* 16GB of memory
* 4 cpus

The Minikube machine is deployed with 4GB of RAM, and 2 vCPUs, and the target
hosts with 4 vCPUs and 4GB of RAM.

### Environment variables

Select:

```sh
export CAPM3_VERSION=v1alpha4
export CAPI_VERSION=v1alpha3
```

or

```sh
export CAPM3_VERSION=v1alpha5
export CAPI_VERSION=v1alpha4
```

or

```sh
export CAPM3_VERSION=v1beta1
export CAPI_VERSION=v1beta1
```

The following environment variables need to be set for **Centos**:

```sh
export IMAGE_OS=Centos
```

And the following environment variables need to be set for **Ubuntu**:

```sh
export IMAGE_OS=Ubuntu
```

And the following environment variables need to be set for **Flatcar**:

```sh
export IMAGE_OS=Flatcar
```

You can check a list of all the environment variables [here](vars.md)

### Deploy the metal3 Dev env

```sh
./01_prepare_host.sh
./02_configure_host.sh
./03_launch_mgmt_cluster.sh
```

or

```sh
make
```

### Deploy the target cluster

```sh
./scripts/provision/cluster.sh
./scripts/provision/controlplane.sh
./scripts/provision/worker.sh
```

### Pivot to the target cluster

```sh
./scripts/provision/pivot.sh
```

### Delete the target cluster

```sh
kubectl delete cluster "${CLUSTER_NAME:-"test1"}" -n metal3
```

### Deploying with Tilt

It is possible to use Tilt to run the CAPI, BMO and CAPM3 components. For this, run:

```sh
export EPHEMERAL_CLUSTER="tilt"
make
```

Then clone the Cluster API Provider Metal3 repository, and follow the
[instructions](https://github.com/metal3-io/cluster-api-provider-metal3/blob/main/docs/dev-setup.md#tilt-development-environment).
That will mostly be the three following blocks of commands.

```sh
source lib/common.sh
source lib/network.sh
source lib/images.sh
```

and go to the CAPM3 repository and run

```sh
make tilt-settings
```

Please refer to the CAPM3 instructions to include BMO and IPAM. Then run :

```sh
make tilt-up
```

Once the cluster is running, you can create the BareMetalHosts :

```sh
kubectl create namespace metal3
kubectl apply -f examples/metal3crds/metal3.io_baremetalhosts.yaml
kubectl apply -n metal3 -f /opt/metal3-dev-env/bmhosts_crs.yaml
```

Afterwards, you can deploy a target cluster.

If you are running tilt on a remote machine, you can forward the web interface
by adding the following parameter to the ssh command `-L 10350:127.0.0.1:10350`

Then you can access the Tilt dashboard locally [here](http://127.0.0.1:10350)

### Recreating local ironic containers

In case, you want recreate the local ironic containers enabled with TLS, you
need to use the following instructions:

```sh
source lib/common.sh
source lib/network.sh

export IRONIC_HOST="${CLUSTER_URL_HOST}"
export IRONIC_HOST_IP="${CLUSTER_PROVISIONING_IP}"

source lib/ironic_tls_setup.sh
source lib/ironic_basic_auth.sh

cd ${BMOPATH}
./tools/run_local_ironic.sh
```

Here `${BMOPATH}` points to the baremetal operator directory. For more
information, regarding the TLS setup and running ironic locally please refer to
these documents:
[TLS](https://github.com/metal3-io/cluster-api-provider-metal3/blob/main/docs/getting-started.md)
, [Run local ironic](https://github.com/metal3-io/baremetal-operator/blob/main/docs/dev-setup.md).
