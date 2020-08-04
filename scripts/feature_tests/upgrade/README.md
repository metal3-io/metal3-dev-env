# Upgrade script naming scheme

* nodes: ```<i>cp | <j>w; i=1..n, j=0..n```; cp = control plane, w = worker
* what: bootDiskImage | k8sVer | k8sBin
* How: scaleInWorkers | scaleOutWorkers
* other: extraNode
* postfix: upgrade | upgrade_both; cp or w depending on the script directory
 or both cp and w

An example would be an upgrade of kubernetes version.
Nodes: 1 controlplane node and 3 worker nodes
What: kubernetes version
how: using scale-in
other: other information
postfix: upgrade or downgrade

So, using the format ```nodes_what_how_other_postfix.sh```, one
can name a test file as follows.

## Example

1cp_3w_k8sVer_scaleInWorkers_upgrade.sh