# V1Alpha2 deployment

The v1alpha2 deployment can be done with Ubuntu 18.04 or Centos 7 target host
images.

## Requirements

### Dev env size

The requirements for the dev env machine are, when deploying **Ubuntu** target
hosts:

* 16GB of memory
* 4 cpus

And when deploying **Centos** target hosts:

* 32GB of memory
* 4 cpus

The Minikube machine is deployed with 4GB of RAM, and 2 vCPUs, and the target
hosts with 4 vCPUs and either 4GB of RAM (Ubuntu) or 8GB of RAM (Centos).

## Environment variables

The following environment variables need to be set for **Centos**:

```sh
export IMAGE_CHECKSUM=http://172.22.0.1/images/centos-updated.qcow2.md5sum
export IMAGE_NAME=centos-updated.qcow2
export CAPI_VERSION=v1alpha2
export IMAGE_URL=http://172.22.0.1/images/centos-updated.qcow2
export IMAGE_OS=Centos
export DEFAULT_HOSTS_MEMORY=8192
```

And the following environment variables need to be set for **Ubuntu**:

```sh
export CAPI_VERSION=v1alpha2
export IMAGE_OS=Ubuntu
export DEFAULT_HOSTS_MEMORY=4096
```

## Deploy the metal3 Dev env

```sh
./01_prepare_host.sh
./02_configure_host.sh
./03_launch_mgmt_cluster.sh
```

## Centos target hosts only, image update

If you want to deploy Ubuntu hosts, please skip to the next section.

If you want to deploy Centos 7 for the target hosts, the Centos 7 image requires
an update of Cloud-init. An updated image can be downloaded
[here](http://artifactory.nordix.org/artifactory/airship/images/centos.qcow2).
You can replace the existing centos image with the following commands :

```sh
curl -LO http://artifactory.nordix.org/artifactory/airship/images/centos.qcow2
mv centos.qcow2 /opt/metal3-dev-env/ironic/html/images/centos-updated.qcow2
md5sum /opt/metal3-dev-env/ironic/html/images/centos-updated.qcow2 | \
awk '{print $1}' > \
/opt/metal3-dev-env/ironic/html/images/centos-updated.qcow2.md5sum
```

## Deploy the target cluster

```sh
./scripts/v1alpha2/create_cluster.sh
./scripts/v1alpha2/create_controlplane.sh
./scripts/v1alpha2/create_worker.sh
```

## Delete the target cluster

```sh
kubectl delete cluster "${CLUSTER_NAME:-"test1"}" -n metal3
```
