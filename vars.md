# Environment variables

The vast majority of configurations for the environment are stored
in `config_${user}.sh`. You can manipulate the values of some
environment variables with allowed values as in this table and it is
recommended modifying or adding variables in `config_${user}.sh` config
file instead of exporting them in the shell. By doing that, it is,
assured that they are persisted.

| Name | Option | Allowed values | Default |
| :------ | :------- | :--------------- | :-------- |
| MAX_SURGE_VALUE | This variable defines if controlplane should scale-in or scale-out during upgrade. | 0 (scale-in) or 1 (scale-out) |1|
| EPHEMERAL_CLUSTER | Tool for running management/ephemeral cluster. | minikube, kind, tilt | "kind" when using docker as the container runtime (the default on Ubuntu), "minikube" otherwise |
| IP_STACK | Choose whether the "baremetal" libvirt network will use IPv4, IPv6, or IPv4+IPv6. This network is the primary network interface for the virtual bare metal hosts. <br/> Note that this only sets up the underlying network, and fully provisioning IPv6 kubernetes clusters is not yet automated. If IPv6 is enabled, DHCPv6 will be available to the virtual bare metal hosts. | "v4", "v6", "v4v6" (dual-stack)) | v4 |
| EXTERNAL_VLAN_ID | If the "baremetal" network is tagged, this is the VLAN id for the network, set on the network interface for the bare metal hosts. | "" or 1-4096 | "" |
| EXTERNAL_SUBNET_V4 | When using IPv4 stack, this is the subnet used on the "baremetal" libvirt network, created as the primary network interface for the virtual bare metalhosts. | IPv4 CIDR | 192.168.111.0/24 |
| EXTERNAL_SUBNET_V6 | When using IPv6 stack, this is the subnet used on the "baremetal" libvirt network, created as the primary network interface for the virtual bare metalhosts. | IPv6 CIDR | fd55::/64 |
| PROVISIONING_IPV6 | Configure provisioning network for single-stack ipv6 | "true", "false" | false |
| SSH_PUB_KEY | This SSH key will be automatically injected into the provisioned host by the clusterctl environment template files. | | ~/.ssh/id_rsa.pub |
| CONTAINER_RUNTIME | Select the Container Runtime | "docker", "podman" | "docker" on ubuntu, "podman" otherwise |
| BMOREPO | Set the Baremetal Operator repository to clone | | https://github.com/metal3-io/baremetal-operator.git |
| BMOBRANCH | Set the Baremetal Operator branch to checkout | | main |
| CAPM3REPO | Set the Cluster Api Metal3 provider repository to clone | | https://github.com/metal3-io/cluster-api-provider-metal3.git |
| CAPM3BRANCH | Set the Cluster Api Metal3 provider branch to checkout | | main |
| FORCE_REPO_UPDATE | Force deletion of the BMO, CAPM3 and IPAM repositories before cloning them again | "true", "false" | "true" |
| IPA_DOWNLOAD_ENABLED | Enables the use of the Ironic Python Agent Downloader container to download IPA archive| "true", "false | "true" |
| USE_LOCAL_IPA | Enables the use of locally supplied IPA archive. This condition is handled by BMO and this has effect only when IPA_DOWNLOAD_ENABLED is "false", otherwise IPA_DOWNLOAD_ENABLED takes precedence. | "true", "false" | "false" |
| LOCAL_IPA_PATH | This has effect only when USE_LOCAL_IPA is set to "true", points to the directory where the IPA archive is located. This variable is handled by BMO. | "arbitrary directory path" | "" |
| BMO_RUN_LOCAL | Run a local baremetal operator instead of deploying in Kubernetes | "true", "false" | "false" |
| CAPM3_RUN_LOCAL | Run a local CAPM3 operator instead of deploying in Kubernetes | "true", "false" | "false" |
| SKIP_RETRIES | Do not retry on failure during verifications or tests of the environment. This should be false. It could only be set to false for verifications of a dev env deployment that fully completed. Otherwise failures will appear as resources are not ready. | "true", "false" | "false" |
| TEST_TIME_INTERVAL | Interval between retries after verification or test failure (seconds) | | 10 |
| TEST_MAX_TIME | Number of maximum verification or test retries | | 120 |
| BMC_DRIVER | Set the BMC driver | "ipmi", "redfish", "redfish-virtualmedia" | "mixed" |
| BOOT_MODE  | Set libvirt firmware and BMH bootMode | "legacy", "UEFI", "UEFISecureBoot" | "legacy" |
| IMAGE_OS | OS of the image to boot the nodes from, overriden by IMAGE\_\* if set | "centos", "cirros", "FCOS", "ubuntu", "flatcar" | "centos" |
| IMAGE_NAME | Image for target hosts deployment | | "CENTOS_8_NODE_IMAGE_K8S_${KUBERNETES_VERSION}.qcow2" |
| IMAGE_LOCATION | Location of the image to download | | https://artifactory.nordix.org/artifactory/metal3/images/${KUBERNETES_VERSION} |
| IMAGE_USERNAME | Image username for ssh | | "metal3" |
| CONTAINER_REGISTRY | Registry to pull metal3 container images from | | "quay.io" |
| DOCKER_HUB_PROXY | Registry to pull docker hub images from | | "docker.io" |
| IRONIC_IMAGE | Container image for local ironic services | | "$CONTAINER_REGISTRY/metal3-io/ironic" |
| VBMC_IMAGE | Container image for vbmc container | | "$CONTAINER_REGISTRY/metal3-io/vbmc" |
| SUSHY_TOOLS_IMAGE | Container image for sushy-tools container | | "$CONTAINER_REGISTRY/metal3-io/sushy-tools" |
| CAPM3_VERSION | Version of Cluster API provider Metal3 | "v1alpha4", "v1alpha5", "v1beta1" | "v1beta1" |
| CAPI_VERSION | Version of Cluster API | "v1alpha3", "v1alpha4", "v1beta1" | "v1beta1" |
| CLUSTER_APIENDPOINT_IP | API endpoint IP for target cluster | "x.x.x.x" | "192.168.111.249" |
| CLUSTER_APIENDPOINT_HOST | API endpoint host for target cluster | | $CLUSTER_APIENDPOINT_IP |
| CLUSTER_APIENDPOINT_PORT | API endpoint port for target cluster | | "6443" |
| CLUSTER_PROVISIONING_INTERFACE | Cluster provisioning Interface | "ironicendpoint" | "ironicendpoint" |
| POD_CIDR | Pod CIDR | "x.x.x.x/x" | "192.168.0.0/18" |
| NODE_HOSTNAME_FORMAT | Node hostname format. This is a format string that must contain exactly one %d format field that will be replaced with an integer representing the number of the node. | "node-%d" |
| KUBERNETES_VERSION | Kubernetes version | "x.x.x" | "1.23.3" |
| UPGRADED_K8S_VERSION | Upgraded Kubernetes version | "x.x.x" | "1.23.3" |
| KUBERNETES_BINARIES_VERSION | Version of kubelet, kubeadm and kubectl | "x.x.x-xx" or "x.x.x" | same as KUBERNETES_VERSION |
| KUBERNETES_BINARIES_CONFIG_VERSION | Version of kubelet.service and 10-kubeadm.conf files | "vx.x.x" | "v0.2.7" |
| NUM_NODES | Set the number of virtual machines to be provisioned. This VMs will be further configured as controlplane or worker Nodes. Note that NUM_OF_CONTROLPLANE_REPLICAS and NUM_OF_WORKER_REPLICAS should sum to this value. | | 2 |
| NUM_OF_CONTROLPLANE_REPLICAS | Set the controlplane replica count in the target cluster. ||1|
| NUM_OF_WORKER_REPLICAS | Set the worker replica count in the target cluster. ||1|
| VM_EXTRADISKS | Add extra disks to the virtual machines provisioned. By default the size of the extra disk is set in the libvirt Ansible role to 8 GB | "true", "false" | "false" |
| VM_EXTRADISKS_FILE_SYSTEM | Create file system to the extra disk. | "ext4", "xfs" | "ext4" |
| VM_EXTRADISKS_MOUNT_DIR | Mount the extra disk to a directory on a host. | | "/mnt/disk2" |
| VM_TPM_EMULATOR | Add TPM2.0 emulator to VMs. | "true", "false" | "false" |
| DEFAULT_HOSTS_MEMORY | Set the default memory size in MB for the virtual machines provisioned. | | 4096 |
| CLUSTER_NAME | Set the name of the target cluster | | test1 |
| IRONIC_TLS_SETUP | Enable TLS for Ironic and inspector | "true", "false" | "true" |
| IRONIC_BASIC_AUTH | Enable HTTP basic authentication for Ironic and inspector | "true", "false" | "true" |
| IRONIC_CA_CERT_B64 | Base 64 encoded CA certificate of Ironic | | |
| IRONIC_CACERT_FILE | Path to the CA certificate of Ironic | | /opt/metal3-dev-env/certs/ironic-ca.pem |
| IRONIC_INSPECTOR_CACERT_FILE | Path to the CA certificate of Ironic inspector | | /opt/metal3-dev-env/certs/ironic-ca.pem |
| IRONIC_CAKEY_FILE | Path to the CA key of Ironic | | /opt/metal3-dev-env/certs/ironic-ca.key |
| IRONIC_INSPECTOR_CAKEY_FILE | Path to the CA key of Ironic inspector | | /opt/metal3-dev-env/certs/ironic-ca.key |
| IRONIC_CERT_FILE | Path to the certificate of Ironic | | /opt/metal3-dev-env/certs/ironic.crt |
| IRONIC_INSPECTOR_CERT_FILE | Path to the CA certificate of Ironic inspector | | /opt/metal3-dev-env/certs/ironic-inspector.crt |
| IRONIC_KEY_FILE | Path to the certificate key of Ironic | | /opt/metal3-dev-env/certs/ironic.key |
| IRONIC_INSPECTOR_KEY_FILE | Path to the certificate key of Ironic inspector | | /opt/metal3-dev-env/certs/ironic-inspector.key |
| IRONIC_USERNAME | Username for Ironic basic auth | | |
| IRONIC_INSPECTOR_USERNAME | Username for Ironic inspector basic auth | | |
| IRONIC_PASSWORD | Password for Ironic basic auth | | |
| IRONIC_INSPECTOR_PASSWORD | Password for Ironic inspector basic auth | | |
| REGISTRY_PORT | Container image registry port | | 5000 |
| HTTP_PORT | Httpd server port | | 6180 |
| IRONIC_INSPECTOR_PORT | Ironic Inspector port | | 5050 |
| IRONIC_API_PORT | Ironic Api port | | 6385 |
| RESTART_CONTAINER_CERTIFICATE_UPDATED | Enable the ironic restart feature when TLS certificates are updated | "true", "false" | "true" |
| NODE_DRAIN_TIMEOUT | Set the nodeDrainTimeout for controlplane and worker template | | '0s' |
| MARIADB_KEY_FILE | Path to the key of MariaDB | | /opt/metal3-dev-env/certs/mariadb.key |
| MARIADB_CERT_FILE | Path to the cert of MariaDB | | /opt/metal3-dev-env/certs/mariadb.crt |
| MARIADB_CAKEY_FILE | Path to the CA key of MariaDB | | /opt/metal3-dev-env/certs/ironic-ca.key |
| MARIADB_CACERT_FILE | Path to the CA certificate of MariaDB | | /opt/metal3-dev-env/certs/ironic-ca.pem |

## Additional networks

By default two libvirt networks are created `baremetal` and `provisioning`
but in some circumstances it can be useful to define additional secondary
networks.

This can also be enabled via environment variables, the
`EXTRA_NETWORK_NAMES` variable defines a list of network names,
and then ipv4, ipv6 or dual stack subnets can be defined as in the
following example (note that the name prefix in the subnet variables
is always uppercase, even if the `EXTRA_NETWORK_NAMES` are lowercase):

```
export EXTRA_NETWORK_NAMES="nmstate1 nmstate2"
export NMSTATE1_NETWORK_SUBNET_V4='192.168.221.0/24'
export NMSTATE1_NETWORK_SUBNET_V6='fd2e:6f44:5dd8:ca56::/120'
export NMSTATE2_NETWORK_SUBNET_V4='192.168.222.0/24'
export NMSTATE2_NETWORK_SUBNET_V6='fd2e:6f44:5dd8:cc56::/120'
```
