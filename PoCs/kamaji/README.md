# Kamaji + Metal3 workload clusters

Kamaji can be used as control-plane provider together with Metal3 as
infrastructure provider to create workload clusters. This directory contains an
example of how to do this.

## Requirements

Tested on ubuntu 24.04 with the following:

- docker
- kind
- clusterctl
- kubectl
- libvirt
- virt-install
- htpasswd

## Usage

```bash
# Create a bootstrap cluster
make setup
# Create a workload cluster
make cluster
# Pivot to make the workload cluster the management cluster
make pivot
# Install Kamaji in the management cluster and create a workload cluster
make kamaji
```

After this, you can access the management cluster and the workload cluster like
this:

```bash
# Management cluster
kubectl --kubeconfig=kubeconfig.yaml get nodes
# Workload cluster
clusterctl --kubeconfig=kubeconfig.yaml get kubeconfig kamaji-1 > hosted-kubeconfig.yaml
kubectl --kubeconfig=hosted-kubeconfig.yaml get nodes
```

Example commands:

```console
❯ kubectl --kubeconfig=kubeconfig.yaml get nodes
NAME        STATUS   ROLES           AGE   VERSION
bmo-e2e-0   Ready    control-plane   33m   v1.33.0
bmo-e2e-1   Ready    <none>          32m   v1.33.0
❯ kubectl --kubeconfig=kubeconfig.yaml get bmh
NAME        STATE         CONSUMER                  ONLINE   ERROR   AGE
bmo-e2e-0   provisioned   test-1-pb6tm              true             24m
bmo-e2e-1   provisioned   md-test-1-cvd5p-474jx     true             24m
bmo-e2e-2   provisioned   md-kamaji-1-qmrf9-865xn   true             24m
❯ kubectl --kubeconfig=kubeconfig.yaml get machines
NAME                      CLUSTER    NODENAME    PROVIDERID                                           PHASE     AGE   VERSION
md-kamaji-1-qmrf9-865xn   kamaji-1   bmo-e2e-2   metal3://default/bmo-e2e-2/md-kamaji-1-qmrf9-865xn   Running   40m   v1.33.0
md-test-1-cvd5p-474jx     test-1     bmo-e2e-1   metal3://default/bmo-e2e-1/md-test-1-cvd5p-474jx     Running   62m   v1.33.0
test-1-pb6tm              test-1     bmo-e2e-0   metal3://default/bmo-e2e-0/test-1-pb6tm              Running   62m   v1.33.0
❯ # Hosted workload cluster
❯ kubectl --kubeconfig=hosted-kubeconfig.yaml get nodes
NAME        STATUS   ROLES    AGE   VERSION
bmo-e2e-2   Ready    <none>   39m   v1.33.0
❯ kubectl --kubeconfig=hosted-kubeconfig.yaml get pods -A
NAMESPACE     NAME                                       READY   STATUS    RESTARTS   AGE
kube-system   calico-kube-controllers-689744956f-56nqs   1/1     Running   0          69m
kube-system   calico-node-hf4kp                          1/1     Running   0          62m
kube-system   coredns-796d84c46b-2wd44                   1/1     Running   0          79m
kube-system   coredns-796d84c46b-qstbs                   1/1     Running   0          79m
kube-system   kube-proxy-6rx9p                           1/1     Running   0          62m
```

## Cleanup

```bash
# Clean the clusters and node images
make clean
# If you want to keep the images and just clean the rest:
make teardown
```
