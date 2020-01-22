Metal³ Development Environment
==============================

[![Ubuntu V1alpha1 build status](https://jenkins.nordix.org/view/Airship/job/airship_master_integration_test_ubuntu/badge/icon?subject=Ubuntu%20E2E%20V1alpha1)](https://jenkins.nordix.org/view/Airship/job/airship_master_integration_test_ubuntu)
[![CentOS V1alpha1 build status](https://jenkins.nordix.org/view/Airship/job/airship_master_integration_test_centos/badge/icon?subject=CentOS%20E2E%20V1alpha1)](https://jenkins.nordix.org/view/Airship/job/airship_master_integration_test_centos)
[![Ubuntu V1alpha2 build status](https://jenkins.nordix.org/view/Airship/job/airship_master_v1a2_integration_test_ubuntu/badge/icon?subject=Ubuntu%20E2E%20V1alpha2)](https://jenkins.nordix.org/view/Airship/job/airship_master_v1a2_integration_test_ubuntu)
[![CentOS V1alpha2 build status](https://jenkins.nordix.org/view/Airship/job/airship_master_v1a2_integration_test_centos/badge/icon?subject=CentOS%20E2E%20V1alpha2)](https://jenkins.nordix.org/view/Airship/job/airship_master_v1a2_integration_test_centos)

**Metal³** project (pronounced: Metal Kubed) exists to provide components that
allow you to do bare metal host management for Kubernetes. Metal³ works as a
Kubernetes application, meaning it runs on Kubernetes and is managed through
Kubernetes interfaces. Metal³ development environment is aimed to set up an
emulated environment which creates a set of Virtual Machines (VMs) to manage as
if they were bare metal hosts.

Before you begin
------------

The minimum requirements for the machine hosting Metal³-dev-env can be
different based on the type of a distribution for the target node.

| Target distribution | host CPU | host memory (Gb) |
|---------------------|----------|------------------|
|         CentOS      |     4    |        32        |
|         Cirros      |     4    |        16        |
|         Ubuntu      |     4    |        16        |

Environment variables
------------

| Variable |  Choices | Comments | Default |
|----------|----------|----------|---------|
| CAPI_VERSION | v1alpha1 / v1alpha2 | Cluster API version to use | v1alpha1 |
| IMAGE_OS | Centos / Cirros / Ubuntu  |  Distribution to use for the target node | Centos |
| DEFAULT_HOSTS_MEMORY | 4096 / 8192  | Memory size for the target node in Mb | 4096 |
| CONTAINER_RUNTIME | podman / docker | Container runtime  | podman |

To see the list of all available environment variables check
[here:](https://metal3.io/try-it.html#setup)

Quick start: Deploying Metal³-dev-env
------------

[![asciicast](https://asciinema.org/a/295294.png)](https://asciinema.org/a/VanYI09TcGdod7YnII1cBqFhY?speed=3&theme=tango)

Please follow the steps below to build Metal3 dev environment.
```bash
# clone the Metal³-dev-env github repo
$ git clone https://github.com/metal3-io/metal3-dev-env.git
$ cd ./metal3-dev-env
# export environment variables depending on your need
$ export CAPI_VERSION=v1alpha1
$ export IMAGE_OS=Centos
$ export DEFAULT_HOSTS_MEMORY=8192
$ export CONTAINER_RUNTIME=docker
# Deploy the Metal³-dev-env
$ ./01_prepare_host.sh
$ ./02_configure_host.sh
$ ./03_launch_mgmt_cluster.sh
```

You should see the following four pods are created and running in ``metal3``
namespace

```bash
$ kubectl get pods -n metal3
NAME                                         READY   STATUS    RESTARTS   AGE
cabpk-controller-manager-5c67dd56c4-jdrgk    2/2     Running   0          25m
capbm-controller-manager-7f9b8f96b7-mb4cm    2/2     Running   0          25m
capi-controller-manager-798c76675f-sg5fs     1/1     Running   0          25m
metal3-baremetal-operator-5cbbd7b87d-f4ktc   6/6     Running   0          25m
```
You should see that there are two baremetal hosts (bmh) ``node-0`` and
``node-1`` in a ready state, each with a unique BMC endpoint address.

```bash
$ kubectl get baremetalhosts -n metal3
NAME     STATUS   PROVISIONING STATUS   CONSUMER   BMC                         HARDWARE PROFILE   ONLINE   ERROR
node-0   OK       ready                            ipmi://192.168.111.1:6230   unknown            true     
node-1   OK       ready                            ipmi://192.168.111.1:6231   unknown            true     
```
Congratulations!  You have now Metal³ development environment ready to use.

Provision Cluster and Machines
------------

Once you have successfully built Metal³-dev-env, you can start creating a
cluster and set of machines, where one is Kubernetes master node and the second
is a worker node. Following script will apply
[Cluster custom resource](https://github.com/metal3-io/metal3-dev-env/blob/master/crs/v1alpha2/cluster.yaml)
(CR) to provision a cluster in ``metal3`` namespace.

```bash
$ ./scripts/v1alpha1/create_cluster.sh
cluster.cluster.x-k8s.io/test1 created
baremetalcluster.infrastructure.cluster.x-k8s.io/test1 created

# check that cluster is provisioned
$ kubectl get cluster -n metal3
NAME    PHASE
test1   provisioned
```

Next, run ``create_controlplane.sh`` script to create a master machine,
baremetalmachine and its associated KubeadmConfig in  ``metal3`` namespace.

```bash
$ ./scripts/v1alpha1/create_controlplane.sh
machine.cluster.x-k8s.io/test1-controlplane-0 created
baremetalmachine.infrastructure.cluster.x-k8s.io/test1-controlplane-0 created
kubeadmconfig.bootstrap.cluster.x-k8s.io/test1-controlplane-0 created

# check that one of the machine provisioning started
$ kubectl get bmh -n metal3
NAME     STATUS   PROVISIONING STATUS   CONSUMER               BMC                         HARDWARE PROFILE   ONLINE   ERROR
node-0   OK       ready                                        ipmi://192.168.111.1:6230   unknown            true     
node-1   OK       provisioning          test1-controlplane-0   ipmi://192.168.111.1:6231   unknown            true     
```

Next, run the ``create_worker.sh`` script to create the worker machine,
baremetalmachine and its associated KubeadmConfig in ``metal3`` namespace.

```bash
$ ./scripts/v1alpha1/create_worker.sh
machinedeployment.cluster.x-k8s.io/test1-md-0 created
baremetalmachinetemplate.infrastructure.cluster.x-k8s.io/test1-md-0 created
kubeadmconfigtemplate.bootstrap.cluster.x-k8s.io/test1-md-0 created

# check if controller machine provisioned started
$ kubectl get bmh -n metal3
NAME     STATUS   PROVISIONING STATUS   CONSUMER               BMC                         HARDWARE PROFILE   ONLINE   ERROR
node-0   OK       provisioning          test1-md-0-m87bq       ipmi://192.168.111.1:6230   unknown            true     
node-1   OK       provisioned           test1-controlplane-0   ipmi://192.168.111.1:6231   unknown            true     
```

At this point can see that ``node-1`` is provisioned while ``node-0`` is
provisioning.

To find an IP addresses of each node, you can check the DHCP leases on the
``baremetal`` libvirt network.

```bash
$ sudo virsh net-dhcp-leases baremetal
Expiry Time          MAC address        Protocol  IP address                Hostname        Client ID or DUID
-------------------------------------------------------------------------------------------------------------------
2020-01-21 20:56:49  00:de:4d:8d:dd:c4  ipv4      192.168.111.20/24         node-0          -
2020-01-21 20:41:01  00:de:4d:8d:dd:c8  ipv4      192.168.111.21/24         node-1          -
```

Next, SSH to the target cluster node: ``node-1`` which is a master node in
this case. Metal3 host machine's SSH public key will be injected into the
target node VM.

```bash
$ ssh ubuntu@192.168.111.21

# once you are on the target node, you should see running pods
$ kubectl get pods -A
NAMESPACE     NAME                             READY   STATUS    RESTARTS   AGE
kube-system   coredns-6955765f44-nnfsf         0/1     Pending   0          52m
kube-system   coredns-6955765f44-nrrcq         0/1     Pending   0          52m
kube-system   etcd-node-1                      1/1     Running   0          52m
kube-system   kube-apiserver-node-1            1/1     Running   0          52m
kube-system   kube-controller-manager-node-1   1/1     Running   0          52m
kube-system   kube-proxy-9tmvb                 1/1     Running   0          52m
kube-system   kube-proxy-nfln4                 1/1     Running   0          13m
kube-system   kube-scheduler-node-1            1/1     Running   0          52m

$ kubectl get nodes
NAME     STATUS     ROLES    AGE   VERSION
node-0   NotReady   <none>   16m   v1.17.2
node-1   NotReady   master   55m   v1.17.2
```
At this point you can see that target Kubernetes cluster with one master and
worker node is  deployed, but node status is in ``NotReady`` as we need to
install Container Networking Interface (CNI), which is in this case
[Calico](https://www.projectcalico.org/). To install Calico, please follow the
steps from its
[documentation](https://docs.projectcalico.org/v3.9/getting-started/kubernetes/installation/calico).

After installing Calico you should see the status of nodes in ``Ready`` and
calica pods in running state as well.

```bash
$ kubectl get nodes
NAME     STATUS   ROLES    AGE    VERSION
node-0   Ready    <none>   78m    v1.17.2
node-1   Ready    master   117m   v1.17.2

NAMESPACE     NAME                                       READY   STATUS    RESTARTS   AGE
kube-system   calico-kube-controllers-6b9d4c8765-gmxx5   1/1     Running   0          4m54s
kube-system   calico-node-lnfcv                          1/1     Running   0          4m54s
kube-system   calico-node-xkfk6                          1/1     Running   0          4m54s
kube-system   coredns-6955765f44-nnfsf                   1/1     Running   0          120m
kube-system   coredns-6955765f44-nrrcq                   1/1     Running   0          120m
kube-system   etcd-node-1                                1/1     Running   0          120m
kube-system   kube-apiserver-node-1                      1/1     Running   0          120m
kube-system   kube-controller-manager-node-1             1/1     Running   0          120m
kube-system   kube-proxy-9tmvb                           1/1     Running   0          120m
kube-system   kube-proxy-nfln4                           1/1     Running   0          81m
kube-system   kube-scheduler-node-1                      1/1     Running   0          120m
```

Deprovision Cluster and Machines
------------

You can run the following scripts to deprovision your target cluster and
machines.

```bash
$ ./scripts/v1alpha1/delete_worker.sh
machinedeployment.cluster.x-k8s.io "test1-md-0" deleted
baremetalmachinetemplate.infrastructure.cluster.x-k8s.io "test1-md-0" deleted
kubeadmconfigtemplate.bootstrap.cluster.x-k8s.io "test1-md-0" deleted

$ ./scripts/v1alpha1/delete_controlplane.sh
machine.cluster.x-k8s.io "test1-controlplane-0" deleted
baremetalmachine.infrastructure.cluster.x-k8s.io "test1-controlplane-0" deleted
kubeadmconfig.bootstrap.cluster.x-k8s.io "test1-controlplane-0" deleted

$ ./scripts/v1alpha1/delete_cluster.sh
cluster.cluster.x-k8s.io "test1" deleted
baremetalcluster.infrastructure.cluster.x-k8s.io "test1" deleted
```

Tear down Metal³ dev environment.
------------

**Note:** If you used docker as container runtime when building dev environment,
make sure that current session still has ``CONTAINER_RUNTIME=docker``
exported. Otherwise, it can interfere while rebuilding dev environment with
default container runtime (podman).

```bash
$ make clean
```

Contributing to Metal³
------------

All the contirubutions, questions, bug/issue reports are very welcomed!
You can reach Metal³ community members through:
* Kubernetes [Slack](https://kubernetes.slack.com/messages/CHD49TLE7)
channel **#cluster-api-baremetal**
* [Google groups mailing list](https://groups.google.com/forum/#!forum/metal3-dev).

If you find a bug/issue or want to extend project's functionality, you can
report it here : https://github.com/metal3-io/metal3-dev-env/issues.

Community meeting
------------

* Bi-Weekly Community Meetings every alternate Wednesday at 14:00 UTC on
[Zoom](https://zoom.us/j/781102362)
* Previous meetings: [recording](https://www.youtube.com/playlist?list=PL3piInrK5Z0fKv7dwBU71Mn58LngdqOKA)
* Project Document: [here](https://docs.google.com/document/d/1d7jqIgmKHvOdcEmE2v72WDZo9kz7WwhuslDOili25Ls/edit)

License
------------

Metal3 is licenced under
[Apache License 2.0](http://www.apache.org/licenses/LICENSE-2.0.txt)
