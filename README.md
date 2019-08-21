Metal³ Development Environment
==============================

This repository includes scripts to set up a Metal³ development environment.

   * [Instructions](#instructions)
      * [Prerequisites](#prerequisites)
      * [Setup](#setup)
   * [Working with the Environment](#working-with-the-environment)
      * [Bare Metal Hosts](#bare-metal-hosts)
      * [Provisioning a Machine](#provisioning-a-machine)
      * [Directly Provisioning Bare Metal Hosts](#directly-provisioning-bare-metal-hosts)
      * [Running a Custom baremetal-operator](#running-a-custom-baremetal-operator)
      * [Accessing the Ironic API](#accessing-the-ironic-api)

# Instructions

## Prerequisites

 * System with CentOS 7 or Ubuntu 18.04
 * Bare metal preferred, as we will be creating VMs to emulate bare metal hosts
 * run as a user with passwordless sudo access

## Setup

tl;dr - Run `make`.

The `Makefile` runs a series of scripts, described here:

* `01_install_requirements.sh` - Installs all needed packages.

* `02_configure_host.sh` - Create a set of VMs that will be managed as if they
  were bare metal hosts.

* `03_launch_mgmt_cluster.sh` - Launch a management cluster using `minikube` and
  run the `baremetal-operator` on that cluster.

* `04_verify.sh` - Runs a set of tests that verify that the deployment completed
  successfully

To tear down the environment, run `make clean`.

You can also run some tests provisioning and deprovisioning machines by running
`make test`

## Note
If you see this error during the installation:

```sh
error: failed to connect to the hypervisor
error: Failed to connect socket to '/var/run/libvirt/libvirt-sock': Permission denied
```
You may need to log out then login again, and run `make` again.

# Working with the Environment

## Bare Metal Hosts

This environment creates a set of VMs to manage as if they were bare metal
hosts.  You can see the VMs using `virsh`.

```sh
$ sudo virsh list
 Id    Name                           State
----------------------------------------------------
 6     minikube                       running
 9     kube_worker_0                  running
 10    kube_master_0                  running
```

Each of the VMs (aside from the `minikube` management cluster VM) are
represented by `BareMetalHost` objects in our management cluster.  The yaml
used to create these host objects is in `bmhosts_crs.yaml`.

```sh
$ kubectl get baremetalhosts -n metal3
NAME       STATUS    PROVISIONING STATUS   MACHINE   BMC                         HARDWARE PROFILE   ONLINE    ERROR
master-0   OK        ready                           ipmi://192.168.111.1:6230   unknown            true      
worker-0   OK        ready                           ipmi://192.168.111.1:6231   unknown            true      
```

You can also look at the details of a host, including the hardware information
gathered by doing pre-deployment introspection.

```sh
$ kubectl get baremetalhost -n metal3 -oyaml worker-0
apiVersion: metal3.io/v1alpha1
kind: BareMetalHost
metadata:
  annotations:
    kubectl.kubernetes.io/last-applied-configuration: |
      {"apiVersion":"metal3.io/v1alpha1","kind":"BareMetalHost","metadata":{"annotations":{},"name":"worker-0","namespace":"metal3"},"spec":{"bmc":{"address":"ipmi://192.168.111.1:6231","credentialsName":"worker-0-bmc-secret"},"bootMACAddress":"00:c2:fc:3b:8e:b5","online":true}}
  creationTimestamp: 2019-05-27T14:16:07Z
  finalizers:
  - baremetalhost.metal3.io
  generation: 2
  name: worker-0
  namespace: metal3
  resourceVersion: "1180"
  selfLink: /apis/metal3.io/v1alpha1/namespaces/metal3/baremetalhosts/worker-0
  uid: f878526e-8089-11e9-93f1-3c93b777d2dc
spec:
  bmc:
    address: ipmi://192.168.111.1:6231
    credentialsName: worker-0-bmc-secret
  bootMACAddress: 00:c2:fc:3b:8e:b5
  description: ""
  hardwareProfile: ""
  online: true
status:
  errorMessage: ""
  goodCredentials:
    credentials:
      name: worker-0-bmc-secret
      namespace: metal3
    credentialsVersion: "802"
  hardware:
    cpu:
      count: 4
      model: Intel(R) Xeon(R) CPU E5-2630 v4 @ 2.20GHz
      speedGHz: 2.199996
      type: x86_64
    nics:
    - ip: 192.168.111.21
      mac: 00:c2:fc:3b:8e:b7
      model: 0x1af4 0x0001
      name: eth1
      network: Pod Networking
      speedGbps: 0
    - ip: 172.22.0.32
      mac: 00:c2:fc:3b:8e:b5
      model: 0x1af4 0x0001
      name: eth0
      network: Pod Networking
      speedGbps: 0
    ramGiB: 7
    storage:
    - hctl: "2:0:0:0"
      model: QEMU HARDDISK
      name: /dev/sda
      serialNumber: drive-scsi0-0-0-0
      sizeGiB: 50
      type: HDD
      vendor: QEMU
    systemVendor:
      manufacturer: Red Hat
      productName: KVM
      serialNumber: ""
  hardwareProfile: unknown
  lastUpdated: 2019-05-27T14:20:27Z
  operationalStatus: OK
  poweredOn: true
  provisioning:
    ID: 36dac1b9-a2ec-40b0-98b7-89dc13ca6e29
    image:
      checksum: ""
      url: ""
    state: ready
```

## Provisioning a Machine

This section describes how to trigger provisioning of a host via `Machine`
objects as part of the `cluster-api` integration.

First, run the `create_machine.sh` script to create a `Machine`.  The argument
is a name, and does not have any special meaning.

```sh
$ ./create_machine.sh centos

secret/centos-user-data created
machine.cluster.k8s.io/centos created
```

At this point, the `Machine` actuator will respond and try to claim a
`BareMetalHost` for this `Machine`.  You can check the logs of the actuator
here:

```sh
$ kubectl logs -n metal3 pod/cluster-api-provider-baremetal-controller-manager-0 -c manager

{“level”:”info”,”ts”:1557509343.85325,”logger”:”baremetal-controller-manager”,”msg”:”Found API group metal3.io/v1alpha1”}
{“level”:”info”,”ts”:1557509344.0471826,”logger”:”kubebuilder.controller”,”msg”:”Starting EventSource”,”controller”:”machine-controller”,”source”:”kind source: /, Kind=”}
{“level”:”info”,”ts”:1557509344.14783,”logger”:”kubebuilder.controller”,”msg”:”Starting Controller”,”controller”:”machine-controller”}
{“level”:”info”,”ts”:1557509344.248105,”logger”:”kubebuilder.controller”,”msg”:”Starting workers”,”controller”:”machine-controller”,”worker count”:1}
2019/05/10 17:32:33 Checking if machine centos exists.
2019/05/10 17:32:33 Machine centos does not exist.
2019/05/10 17:32:33 Creating machine centos .
2019/05/10 17:32:33 2 hosts available
2019/05/10 17:32:33 Associating machine centos with host worker-0
2019/05/10 17:32:33 Finished creating machine centos .
2019/05/10 17:32:33 Checking if machine centos exists.
2019/05/10 17:32:33 Machine centos exists.
2019/05/10 17:32:33 Updating machine centos .
2019/05/10 17:32:33 Finished updating machine centos .
```

If you look at the yaml representation of the `Machine`, you will see a new
annotation that identifies which `BareMetalHost` was chosen to satisfy this
`Machine` request.

```sh
$ kubectl get machine centos -n metal3 -o yaml

...
  annotations:
    metal3.io/BareMetalHost: metal3/worker-0
...
```

You can also see in the list of `BareMetalHosts` that one of the hosts is now
provisioned and associated with a `Machine`.

```sh
$ kubectl get baremetalhosts -n metal3

NAME       STATUS    PROVISIONING STATUS   MACHINE   BMC                         HARDWARE PROFILE   ONLINE    ERROR
master-0   OK        ready                           ipmi://192.168.111.1:6230   unknown            true      
worker-0   OK        provisioning          centos    ipmi://192.168.111.1:6231   unknown            true      
```

You should be able to ssh into your host once provisioning is complete.  See
the libvirt DHCP leases to find the IP address for the host that was
provisioned.  In this case, it’s `worker-0`.

```sh
$ sudo virsh net-dhcp-leases baremetal

 Expiry Time          MAC address        Protocol  IP address                Hostname        Client ID or DUID
-------------------------------------------------------------------------------------------------------------------
 2019-05-06 19:03:46  00:1c:cc:c6:29:39  ipv4      192.168.111.20/24         master-0        -
 2019-05-06 19:04:18  00:1c:cc:c6:29:3d  ipv4      192.168.111.21/24         worker-0        -
```

The default user for the CentOS image is `centos`.

```sh
ssh centos@192.168.111.21
```

Deprovisioning is done just by deleting the `Machine` object.

```sh
$ kubectl delete machine centos -n metal3

machine.cluster.k8s.io "centos" deleted
```

At this point you can see that the `BareMetalHost` is going through a
deprovisioning process.

```sh
$ kubectl get baremetalhosts -n metal3

NAME       STATUS   PROVISIONING STATUS   MACHINE   BMC                         HARDWARE PROFILE   ONLINE   ERROR
master-0   OK       ready                           ipmi://192.168.111.1:6230   unknown            true     
worker-0   OK       deprovisioning                  ipmi://192.168.111.1:6231   unknown            false    
```

## Directly Provisioning Bare Metal Hosts

It’s also possible to provision via the `BareMetalHost` interface directly
without using the `cluster-api` integration.

There is a helper script available to trigger provisioning of one of these
hosts.  To provision a host with CentOS 7, run:

```sh
$ ./provision_host.sh worker-0
```

The `BareMetalHost` will go through the provisioning process, and will
eventually reboot into the operating system we wrote to disk.

```sh
$ kubectl get baremetalhost worker-0 -n metal3
NAME       STATUS   PROVISIONING STATUS   MACHINE   BMC                         HARDWARE PROFILE   ONLINE   ERROR
worker-0   OK       provisioned                     ipmi://192.168.111.1:6231   unknown            true     
```

`provision_host.sh` will inject your SSH public key into the VM. To find the IP
address, you can check the DHCP leases on the `baremetal` libvirt network.

```sh
$ sudo virsh net-dhcp-leases baremetal

 Expiry Time          MAC address        Protocol  IP address                Hostname        Client ID or DUID
-------------------------------------------------------------------------------------------------------------------
 2019-05-06 19:03:46  00:1c:cc:c6:29:39  ipv4      192.168.111.20/24         master-0        -
 2019-05-06 19:04:18  00:1c:cc:c6:29:3d  ipv4      192.168.111.21/24         worker-0        -
```

The default user for the CentOS image is `centos`.

```sh
ssh centos@192.168.111.21
```

There is another helper script to deprovision a host.

```sh
$ ./deprovision_host.sh worker-0
```

You will then see the host go into a `deprovisioning` status:

```sh
$ kubectl get baremetalhost worker-0 -n metal3
NAME       STATUS   PROVISIONING STATUS   MACHINE   BMC                         HARDWARE PROFILE   ONLINE   ERROR
worker-0   OK       deprovisioning                  ipmi://192.168.111.1:6231   unknown            true
```

## Running a Custom baremetal-operator

The `baremetal-operator` comes up running in the cluster by default, using an
image built from the `metal3-io/baremetal-operator` github repository.  If
you’d like to test changes to the `baremetal-operator`, you can follow this
process.

First, you must scale down the deployment of the `baremetal-operator` running
in the cluster.

```sh
kubectl scale deployment metal3-baremetal-operator -n metal3 --replicas=0
```

To be able to run `baremetal-operator` locally, you need to install `operator-sdk` https://github.com/operator-framework. After that, you can run the `baremetal-operator` including any custom changes.

```sh
cd ~/go/src/github.com/metal3-io/baremetal-operator
make run
```

## Running a Custom cluster-api-provider-baremetal

There are two cluster-api related managers running in the cluster.  One
includes set of generic controllers, and the other includes a custom Machine
controller for baremetal.  If you want to try changes to
`cluster-api-provider-baremetal`, you want to shut down the custom Machine
controller manager first.

```sh
$ kubectl scale statefulset cluster-api-provider-baremetal-controller-manager -n metal3 --replicas=0
```

Then you can run the custom Machine controller manager out of your local git tree.

```sh
cd ~/go/src/github.com/metal3-io/cluster-api-provider-baremetal
make run
```

## Accessing the Ironic API

Sometimes you may want to look directly at Ironic to debug something.  You can
do this with the `openstack` command.

First you must set these environment variables:

```sh
export OS_TOKEN=fake-token
export OS_URL=http://localhost:6385/
```

Example:

```sh
$ openstack baremetal node list
+--------------------------------------+----------+---------------+-------------+--------------------+-------------+
| UUID                                 | Name     | Instance UUID | Power State | Provisioning State | Maintenance |
+--------------------------------------+----------+---------------+-------------+--------------------+-------------+
| 882cf206-d688-43fa-bf4c-3282fcb00b12 | master-0 | None          | None        | enroll             | False       |
| ac257479-d6c6-47c1-a649-64a88e6ff312 | worker-0 | None          | None        | enroll             | False       |
+--------------------------------------+---------------+---------------+-------------+--------------------+-------------+
```
