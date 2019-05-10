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
NAME            STATUS   PROVISIONING STATUS   MACHINE   BMC                         HARDWARE PROFILE   ONLINE   ERROR
kube-master-0   OK       ready                           ipmi://192.168.111.1:6230   unknown            true     
kube-worker-0   OK       ready                           ipmi://192.168.111.1:6233   unknown            true     
```

You can also look at the details of a host, including the hardware information
gathered by doing pre-deployment introspection.

```sh
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

# Provisioning a Machine

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
2019/05/10 17:32:33 Associating machine centos with host kube-worker-0
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
    metal3.io/BareMetalHost: metal3/kube-worker-0
...
```

You can also see in the list of `BareMetalHosts` that one of the hosts is now
provisioned and associated with a `Machine`.

```sh
$ kubectl get baremetalhosts -n metal3

NAME            STATUS   PROVISIONING STATUS   MACHINE   BMC                         HARDWARE PROFILE   ONLINE   ERROR
kube-master-0   OK       ready                           ipmi://192.168.111.1:6230   unknown            true     
kube-worker-0   OK       provisioned           centos    ipmi://192.168.111.1:6231   unknown            true     
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

NAME            STATUS   PROVISIONING STATUS   MACHINE   BMC                         HARDWARE PROFILE   ONLINE   ERROR
kube-master-0   OK       ready                           ipmi://192.168.111.1:6230   unknown            true     
kube-worker-0   OK       deprovisioning                  ipmi://192.168.111.1:6231   unknown            false    
```

# Directly Provisioning Bare Metal Hosts

It’s also possible to provision via the `BareMetalHost` interface directly
without using the `cluster-api` integration.

There is a helper script available to trigger provisioning of one of these
hosts.  To provision a host with CentOS 7, run:

```sh
$ ./provision_host.sh kube-worker-0
```

The `BareMetalHost` will go through the provisioning process, and will
eventually reboot into the operating system we wrote to disk.

```sh
$ kubectl get baremetalhost kube-worker-0 -n metal3
NAME            STATUS   PROVISIONING STATUS   MACHINE   BMC                         HARDWARE PROFILE   ONLINE   ERROR
kube-worker-0   OK       provisioned                     ipmi://192.168.111.1:6231   unknown            true     
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
$ ./deprovision_host.sh kube-worker-0
```

You will then see the host go into a `deprovisioning` status:

```sh
$ kubectl get baremetalhost kube-worker-0 -n metal3
NAME            STATUS   PROVISIONING STATUS   MACHINE   BMC                         HARDWARE PROFILE   ONLINE   ERROR
kube-worker-0   OK       deprovisioning                  ipmi://192.168.111.1:6231   unknown            true
```

# Running a Custom baremetal-operator

The `baremetal-operator` comes up running in the cluster by default, using an
image built from the `metal3-io/baremetal-operator` github repository.  If
you’d like to test changes to the `baremetal-operator`, you can follow this
process.

First, you must scale down the deployment of the `baremetal-operator` running
in the cluster.

```sh
kubectl scale deployment metal3-baremetal-operator -n metal3 --replicas=0
```

Then you can run the `baremetal-operator` locally including any custom changes.

```sh
cd ~/go/src/github.com/metal3-io/baremetal-operator
make run
```

# Accessing the Ironic API

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
+--------------------------------------+---------------+---------------+-------------+--------------------+-------------+
| UUID                                 | Name          | Instance UUID | Power State | Provisioning State | Maintenance |
+--------------------------------------+---------------+---------------+-------------+--------------------+-------------+
| 882cf206-d688-43fa-bf4c-3282fcb00b12 | kube-master-0 | None          | None        | enroll             | False       |
| ac257479-d6c6-47c1-a649-64a88e6ff312 | kube-worker-0 | None          | None        | enroll             | False       |
+--------------------------------------+---------------+---------------+-------------+--------------------+-------------+
```
