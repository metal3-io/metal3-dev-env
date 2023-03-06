# Metal³ Development Environment

This repository includes scripts to set up a Metal³ development environment.

## Build Status

[![Ubuntu Integration daily main build status](https://jenkins.nordix.org/buildStatus/icon?job=metal3_daily_main_integration_test_ubuntu&subject=Ubuntu%20daily%20main)](https://jenkins.nordix.org/view/Metal3%20Periodic/job/metal3_daily_main_integration_test_ubuntu/)
[![CentOS Integration daily main build status](https://jenkins.nordix.org/buildStatus/icon?job=metal3_daily_main_integration_test_centos&subject=CentOS%20daily%20main)](https://jenkins.nordix.org/view/Metal3%20Periodic/job/metal3_daily_main_integration_test_centos/)
[![Ubuntu Integration daily release-1.3 build status](https://jenkins.nordix.org/buildStatus/icon?job=metal3_daily_release-1-3_integration_test_ubuntu&subject=Ubuntu%20daily%20release-1.3)](https://jenkins.nordix.org/view/Metal3%20Periodic/job/metal3_daily_release-1-3_integration_test_ubuntu/)
[![CentOS Integration daily release-1.3 build status](https://jenkins.nordix.org/buildStatus/icon?job=metal3_daily_release-1-3_integration_test_centos&subject=CentOS%20daily%20release-1.3)](https://jenkins.nordix.org/view/Metal3%20Periodic/job/metal3_daily_release-1-3_integration_test_centos/)
[![Ubuntu Integration daily release-1.2 build status](https://jenkins.nordix.org/buildStatus/icon?job=metal3_daily_release-1-2_integration_test_ubuntu&subject=Ubuntu%20daily%20release-1.2)](https://jenkins.nordix.org/view/Metal3%20Periodic/job/metal3_daily_release-1-2_integration_test_ubuntu/)
[![CentOS Integration daily release-1.2 build status](https://jenkins.nordix.org/buildStatus/icon?job=metal3_daily_release-1-2_integration_test_centos&subject=CentOS%20daily%20release-1.2)](https://jenkins.nordix.org/view/Metal3%20Periodic/job/metal3_daily_release-1-2_integration_test_centos/)

## Instructions

Instructions can be found here: <https://metal3.io/try-it.html>

## Quickstart

Versions v1alpha5 or v1beta1 are later referred as **v1alphaX**/**v1betaX**.

The v1alphaX or v1betaX deployment can be done with Ubuntu 20.04, 22.04 or
Centos 9 Stream target host images. By default, for Ubuntu based target hosts
we are using Ubuntu 22.04.

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
export IMAGE_OS=centos
```

And the following environment variables need to be set for **Ubuntu**:

```sh
export IMAGE_OS=ubuntu
```

And the following environment variables need to be set for **Flatcar**:

```sh
export IMAGE_OS=flatcar
```

You can check a list of all the environment variables [here](vars.md)

### Deploy the metal3 Dev env

Note: These scripts are invasive and will reconfigure part of the host OS
in addition to package installation, and hence it is recommended to run dev-env
in a VM. Please read the scripts to understand what they do before running them
on your machine.

```sh
./01_prepare_host.sh
./02_configure_host.sh
./03_launch_mgmt_cluster.sh
./04_verify.sh
```

or

```sh
make
```

### Deploy the target cluster

```sh
./tests/scripts/provision/cluster.sh
./tests/scripts/provision/controlplane.sh
./tests/scripts/provision/worker.sh
```

### Pivot to the target cluster

```sh
./tests/scripts/provision/pivot.sh
```

### Delete the target cluster

```sh
kubectl delete cluster "${CLUSTER_NAME:-"test1"}" -n metal3
```

### Deploying and developing with Tilt

It is possible to use Tilt to run the CAPI, BMO, CAPM3 and IPAM components. Tilt
ephemeral cluster will utilize Kind and Docker, so it requires an Ubuntu host.
For this, run:

By default, Metal3 components are not built locally. To develop with Tilt, you
must `export BUILD_[CAPM3|BMO|IPAM|CAPI]_LOCALLY=true`, and then you can edit
the code in `~/go/src/github.com/metal3-io/...` and it will be picked up by
Tilt. You can also specify repository URL, branch and commit with `CAPM3REPO`,
`CAPM3BRANCH` and `CAPM3COMMIT` to make dev-env start the component with your
development branch content. Same for IPAM, BMO and CAPI.
See `vars.md` for more information.

After specifying the components and paths to your liking, bring the cluster up
by setting the ephemeral cluster type to Tilt and image OS to Ubuntu.

```sh
export IMAGE_OS=ubuntu
export EPHEMERAL_CLUSTER="tilt"
make
```

If you are running tilt on a remote machine, you can forward the web interface
by adding the following parameter to the ssh command `-L 10350:127.0.0.1:10350`

Then you can access the Tilt dashboard locally [here](http://127.0.0.1:10350)

*Note*: It is easiest if you configure all these in `config_<username>.sh` file,
which is automatically sourced if it exists.

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
