Metal³ Development Environment
==============================

This repository includes scripts to set up a Metal³ development environment.

Prerequisites:
 * System with CentOS 7
 * Bare metal preferred, as we will be creating VMs to emulate bare metal hosts
 * run as a user with passwordless sudo access

# Instructions

tl;dr - Run `make`.

The `Makefile` runs a series of scripts, described here:

* `01_install_requirements.sh` - Installs all needed packages.

* `02_configure_host.sh` - Create a set of VMs that will be managed as if they
  were bare metal hosts.

* `03_launch_mgmt_cluster.sh` - Launch a management cluster using `minikube` and
  run the `baremetal-operator` on that cluster.

To tear down the environment, run `make clean`.

# Bare Metal Hosts

This environment creates a set of VMs to manage as if they were bare metal
hosts.  You can see the VMs using `virsh`.

```
sudo virsh list
 Id    Name                           State
----------------------------------------------------
 6     minikube                       running
 9     kube_worker_0                  running
 10    kube_master_0                  running
```

Each of the VMs (aside from the `minikube` management cluster VM) are
represented by `BareMetalHost` objects in our management cluster.

```
$ kubectl get baremetalhosts -n metal3
NAME            STATUS   PROVISIONING STATUS   MACHINE   BMC                         HARDWARE PROFILE   ONLINE   ERROR
kube-master-0   OK       ready                           ipmi://192.168.111.1:6230   unknown            true     
kube-worker-0   OK       ready                           ipmi://192.168.111.1:6233   unknown            true     
```

You can also look at the details of a host, including the hardware information
gathered by doing pre-deployment introspection.

```
$ kubectl get baremetalhost -n metal3 -oyaml kube-worker-0
apiVersion: metal3.io/v1alpha1
kind: BareMetalHost
metadata:
  annotations:
    kubectl.kubernetes.io/last-applied-configuration: |
      {"apiVersion":"metal3.io/v1alpha1","kind":"BareMetalHost","metadata":{"annotations":{},"name":"kube-worker-0","namespace":"metal3"},"spec":{"bmc":{"address":"ipmi://192.168.111.1:6233","credentialsName":"kube-worker-0-bmc-secret"},"bootMACAddress":"00:93:1e:b1:74:87","online":true}}
  creationTimestamp: "2019-05-03T18:24:45Z"
  finalizers:
  - baremetalhost.metal3.io
  generation: 2
  name: kube-worker-0
  namespace: metal3
  resourceVersion: "1382"
  selfLink: /apis/metal3.io/v1alpha1/namespaces/metal3/baremetalhosts/kube-worker-0
  uid: ba1d5285-6dd0-11e9-86cf-4c9a6490472b
spec:
  bmc:
    address: ipmi://192.168.111.1:6233
    credentialsName: kube-worker-0-bmc-secret
  bootMACAddress: 00:93:1e:b1:74:87
  hardwareProfile: ""
  online: true
status:
  errorMessage: ""
  goodCredentials:
    credentials:
      name: kube-worker-0-bmc-secret
      namespace: metal3
    credentialsVersion: "807"
  hardware:
    cpu:
      count: 2
      model: Intel(R) Core(TM) i7-7567U CPU @ 3.50GHz
      speedGHz: 3.50401
      type: x86_64
    nics:
    - ip: 172.22.0.54
      mac: 00:93:1e:b1:74:87
      model: 0x1af4 0x0001
      name: eth0
      network: Pod Networking
      speedGbps: 0
    - ip: 192.168.111.23
      mac: 00:93:1e:b1:74:89
      model: 0x1af4 0x0001
      name: eth1
      network: Pod Networking
      speedGbps: 0
    ramGiB: 4
    storage:
    - model: QEMU QEMU HARDDISK
      name: /dev/sda
      sizeGiB: 50
      type: HDD
    - model: '0x1af4 '
      name: /dev/vda
      sizeGiB: 8
      type: HDD
  hardwareProfile: unknown
  lastUpdated: "2019-05-03T18:29:58Z"
  operationalStatus: OK
  poweredOn: true
  provisioning:
    ID: c718759b-518e-446b-afd2-010374971f81
    image:
      checksum: ""
      url: ""
    state: ready
```

There is a helper script available to trigger provisioning of one of these
hosts.  To provision a host with CentOS 7, run:

```
$ ./provision_host.sh kube-worker-0
```

The `BareMetalHost` will go through the provisioning process, and will
eventually reboot into the operating system we wrote to disk.

```
kubectl get baremetalhost kube-worker-0 -n metal3
NAME            STATUS   PROVISIONING STATUS   MACHINE   BMC                         HARDWARE PROFILE   ONLINE   ERROR
kube-worker-0   OK       provisioned                     ipmi://192.168.111.1:6231   unknown            true     
```

# Accessing the Ironic API

Sometimes you may want to look directly at Ironic to debug something.  You can
do this with the `openstack` command.

First you must set these environment variables:

```
export OS_TOKEN=fake-token
export OS_URL=http://localhost:6385/
```

Example:

```
$ openstack baremetal node list
+--------------------------------------+---------------+---------------+-------------+--------------------+-------------+
| UUID                                 | Name          | Instance UUID | Power State | Provisioning State | Maintenance |
+--------------------------------------+---------------+---------------+-------------+--------------------+-------------+
| 882cf206-d688-43fa-bf4c-3282fcb00b12 | kube-master-0 | None          | None        | enroll             | False       |
| ac257479-d6c6-47c1-a649-64a88e6ff312 | kube-worker-0 | None          | None        | enroll             | False       |
+--------------------------------------+---------------+---------------+-------------+--------------------+-------------+
```
