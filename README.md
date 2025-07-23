# Metal³ Development Environment

This repository includes scripts to set up a Metal³ development environment.

## Build Status

[![Ubuntu dev env integration main build status](https://jenkins.nordix.org/buildStatus/icon?job=metal3-periodic-dev-env-integration-test-ubuntu-main&subject=Ubuntu%20dev%20env%20main)](https://jenkins.nordix.org/view/Metal3%20Periodic/job/metal3-periodic-dev-env-integration-test-ubuntu-main/)
[![CentOS dev env integration main build status](https://jenkins.nordix.org/buildStatus/icon?job=metal3-periodic-dev-env-integration-test-centos-main&subject=CentOS%20dev%20env%20main)](https://jenkins.nordix.org/view/Metal3%20Periodic/job/metal3-periodic-dev-env-integration-test-centos-main/)

## Instructions

Instructions can be found here: <https://book.metal3.io/developer_environment/tryit>

## Quickstart

Version v1beta1 is later referred as **v1betaX**.

The v1betaX deployment can be done with Ubuntu 18.04, 20.04, 22.04 or
Centos 9 Stream target host images. By default, for Ubuntu based target hosts
we are using Ubuntu 22.04

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

```sh
export CAPM3_VERSION=v1beta1
export CAPI_VERSION=v1beta2
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

By default the virtualization hypervisor used is kvm. To be able to use it
the nested virtualization needs to be enabled in the host. In case kvm or
nested virtualization are not available it is possible to switch to qemu,
although at this moment there are limitations in the execution and it is
considered as experimental configuration.
To switch to the qemu hypervisor apply the following setting:

```sh
export LIBVIRT_DOMAIN_TYPE=qemu
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

export IRONIC_HOST="${CLUSTER_BARE_METAL_PROVISIONER_HOST}"
export IRONIC_HOST_IP="${CLUSTER_BARE_METAL_PROVISIONER_IP}"

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

### Test Matrix

The following table describes which branches are tested for different test triggers:

<!-- markdownlint-disable MD013 -->

| test suffix  | CAPM3 branch | IPAM branch  | BMO branch/tag  | Keepalived tag | Ironic-image tag | IPA branch    |
| ------------ | ------------ | ------------ | --------------- | -------------- | ---------- | ------------- |
| main         | main         | main         | main            | latest         | latest     | master        |
| release-1-10 | release-1.10 | release-1.10 | release-0.10    | v0.10.0        | v29.0.0    | stable/2025.1 |
| release-1-9  | release-1.9  | release-1.9  | release-0.9     | v0.9.0         | v27.0.0    | bugfix/10.0   |
| release-1-8  | release-1.8  | release-1.8  | release-0.8     | v0.8.0         | v26.0.1    | bugfix/9.13   |
| release-1-7  | release-1.7  | release-1.7  | release-0.6     | v0.6.2         | v24.1.2    | stable/2024.1 |

<!-- markdownlint-enable MD013 -->
