Metal³ Development Environment
==============================

This repository includes scripts to set up a Metal³ development environment.

Prerequisites:
 * System with CentOS 7
 * Bare metal preferred, as we will be creating VMs to emulate bare metal hosts
 * run as a user with passwordless sudo access

# Current Status

This is still a work in progress.

A management cluster will be launched with the `baremetal-operator`.  A set of
`BareMetalHost` objects will be created for the set of VMs we’ve created to
emulate bare metal servers.  Management of the hosts doesn’t work yet, as the
`minikube` VM is lacking a network interface on the `provisioning` network.

# Instructions

tl;dr - Run `make`.

The `Makefile` runs a series of scripts, described here:

* `01_install_requirements.sh` - Installs all needed packages.

* `02_configure_host.sh` - Create a set of VMs that will be managed as if they
  were bare metal hosts.

* `03_launch_mgmt_cluster.sh` - Launch a management cluster using `minikube` and
  run the `baremetal-operator` on that cluster.

To tear down the environment, run `make clean`.

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
| 582c3ecf-6604-432f-9f73-1405a16234af | kube-master-1 | None          | None        | enroll             | False       |
| 886c48fd-6291-4af7-a904-f0b1f5053f0d | kube-master-2 | None          | None        | enroll             | False       |
| ac257479-d6c6-47c1-a649-64a88e6ff312 | kube-worker-0 | None          | None        | enroll             | False       |
+--------------------------------------+---------------+---------------+-------------+--------------------+-------------+
```
