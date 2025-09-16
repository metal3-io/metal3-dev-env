# Environment variables

The vast majority of configurations for the environment are stored
in `config_${user}.sh`. You can manipulate the values of some
environment variables with allowed values as in this table and it is
recommended modifying or adding variables in `config_${user}.sh` config
file instead of exporting them in the shell. By doing that, it is
assured that they are persisted.

<!-- markdownlint-disable MD013 MD034 -->

| Name | Option | Allowed values | Default |
| :------ | :------- | :--------------- | :-------- |
| DOCKER_USE_IPV6_INTERNALLY | Choose whether Docker will use IPv6 internally. | "true", "false" | false |
| ENABLE_NAT64 | Enable NAT64 functionality to emulate IPv6 capable host. | "true", "false" | "false |
| DNS_UPSTREAM | Specify upstream DNS server for locally run DNS. Only used when ENABLE_NAT64 = "true" | IPv4 or IPv6 address | 10.1.0.2 |
| DNS64_PREFIX | Prefix for DNS64 server. Only used when ENABLE_NAT64 = "true" | Any valid prefix | 64:ff9b::/96 |
| LOCAL_DNS_V4 | IPv4 address for local DNS server. Only used when ENABLE_NAT64 = "true". Using loopback is fine, because in the IPv6 setup VMs don't access DNS server over IPv4. | IPv4 address | 127.0.0.2 |
| LOCAL_DNS_V6 | IPv6 address for local DNS server. Only used when ENABLE_NAT64 = "true". NOT RECOMMENDED TO USE LOOPBACK ::1, because then VMs cannot access the server. | IPv6 address | fd00:abcd::1 |
| MAX_SURGE_VALUE | This variable defines if controlplane should scale-in or scale-out during upgrade. | 0 (scale-in) or 1 (scale-out) |1|
| EPHEMERAL_CLUSTER | Tool for running management/ephemeral cluster. | minikube, kind, tilt | "kind" when using docker as the container runtime (the default on Ubuntu), "minikube" otherwise |
| IP_STACK | Choose whether the "external" libvirt network will use IPv4, IPv6, or IPv4+IPv6. This network is the primary network interface for the virtual bare metal hosts. Note that this only sets up the underlying network, and fully provisioning IPv6 kubernetes clusters is not yet automated. If IPv6 is enabled, DHCPv6 will be available to the virtual bare metal hosts. | "v4", "v6", "v4v6" (dual-stack)) | v4 |
| EXTERNAL_VLAN_ID | If the "external" network is tagged, this is the VLAN id for the network, set on the network interface for the bare metal hosts. | "" or 1-4096 | "" |
| EXTERNAL_SUBNET_V4 | When using IPv4 stack, this is the subnet used on the "external" libvirt network, created as the primary network interface for the virtual bare metalhosts. | IPv4 CIDR | 192.168.111.0/24 |
| EXTERNAL_SUBNET_V6 | When using IPv6 stack, this is the subnet used on the "external" libvirt network, created as the primary network interface for the virtual bare metalhosts. | IPv6 CIDR | fd55::/64 |
| BARE_METAL_PROVISIONER_SUBNET_IPV6_ONLY | Configure provisioning network for single-stack ipv6 | "true", "false" | false |
| BARE_METAL_PROVISIONER_NETWORK | Assign a subnet to the provisioner network. If ironic is the provisioner then the Ironic API's will be accessible in this network. | IPv4 CIDR | 172.22.0.0/24 |
| SSH_PUB_KEY | This SSH key will be automatically injected into the provisioned host by the clusterctl environment template files. | | ~/.ssh/id_rsa.pub |
| CONTAINER_RUNTIME | Select the Container Runtime | "docker", "podman" | "docker" on ubuntu, "podman" otherwise |
| IPA_DOWNLOAD_ENABLED | Enables the use of the Ironic Python Agent Downloader container to download IPA archive| "true", "false | "true" |
| USE_LOCAL_IPA | Enables the use of locally supplied IPA archive. This condition is handled by BMO and this has effect only when IPA_DOWNLOAD_ENABLED is "false", otherwise IPA_DOWNLOAD_ENABLED takes precedence. | "true", "false" | "false" |
| LOCAL_IPA_PATH | This has effect only when USE_LOCAL_IPA is set to "true", points to the directory where the IPA archive is located. This variable is handled by BMO. | "arbitrary directory path" | "" |
| BMO_RUN_LOCAL | Run a local baremetal operator instead of deploying in Kubernetes | "true", "false" | "false" |
| CAPM3_RUN_LOCAL | Run a local CAPM3 operator instead of deploying in Kubernetes | "true", "false" | "false" |
| SKIP_RETRIES | Do not retry on failure during verifications or tests of the environment. This should be false. It could only be set to false for verifications of a dev env deployment that fully completed. Otherwise failures will appear as resources are not ready. | "true", "false" | "false" |
| SKIP_APPLY_BMH | Do not apply the BMHs. used usually when the BMHs will be applied later in the tests. | "true", "false" | "false" |
| TEST_TIME_INTERVAL | Interval between retries after verification or test failure (seconds) | | 10 |
| TEST_MAX_TIME | Number of maximum verification or test retries | | 240 |
| BMO_ROLLOUT_WAIT | Number of minutes(Until max 10m that is the default value of deployment.spec.progressDeadlineSeconds) to wait for BMO rollout | | 5 |
| BMC_DRIVER | Set the BMC driver | "ipmi", "redfish", "redfish-virtualmedia", "redfish-uefihttp" | "mixed" |
| BMORELEASEBRANCH | BMO Release branch | "main", "release-0.5", "release-0.6", "release-0.8" | Set via jjb for CI, for local dev it gets default value based on CAPM3 branch |
| BOOT_MODE  | Set libvirt firmware and BMH bootMode | "legacy", "UEFI", "UEFISecureBoot" | "UEFI" |
| IMAGE_OS | OS of the image to boot the nodes from, overriden by IMAGE\_\* if set | "centos", "cirros", "FCOS", "ubuntu", "flatcar" | "centos" |
| IMAGE_NAME | Image for target hosts deployment | | "CENTOS_9_NODE_IMAGE_K8S_${KUBERNETES_VERSION}.qcow2" |
| IMAGE_LOCATION | Location of the image to download | | https://artifactory.nordix.org/artifactory/metal3/images/${KUBERNETES_VERSION} |
| IMAGE_USERNAME | Image username for ssh | | "metal3" |
| CONTAINER_REGISTRY | Registry to pull metal3 container images from | | "quay.io" |
| DOCKER_HUB_PROXY | Registry to pull docker hub images from | | "docker.io" |
| IRONIC_IMAGE | Container image for local ironic services | | "$CONTAINER_REGISTRY/metal3-io/ironic" |
| VBMC_IMAGE | Container image for vbmc container | | "$CONTAINER_REGISTRY/metal3-io/vbmc" |
| SUSHY_TOOLS_IMAGE | Container image for sushy-tools container | | "$CONTAINER_REGISTRY/metal3-io/sushy-tools" |
| FAKE_IPA_IMAGE | Container image for fakeIPA container | | "$CONTAINER_REGISTRY/metal3-io/fake-ipa" |
| FKAS_IMAGE | Container image for fkas container | | "$CONTAINER_REGISTRY/metal3-io/metal3-fkas" |
| CAPM3_VERSION | Version of Cluster API provider Metal3 | "v1beta1" | "v1beta1" |
| CAPI_VERSION | Version of Cluster API | "v1beta2" | "v1beta2" |
| CAPI_NIGHTLY_BUILD | Use nightly versions of CAPI components’ manifests. They are built from CAPI's main branch. | "true", "false" | "false" |
| CLUSTER_APIENDPOINT_IP | API endpoint IP for target cluster | "x.x.x.x" | "${EXTERNAL_SUBNET_VX}.249" |
| CLUSTER_APIENDPOINT_HOST | API endpoint host for target cluster | | $CLUSTER_APIENDPOINT_IP |
| CLUSTER_APIENDPOINT_PORT | API endpoint port for target cluster | | "6443" |
| BARE_METAL_PROVISIONER_INTERFACE | Cluster provisioning Interface | "ironicendpoint" | "ironicendpoint" |
| POD_CIDR | Pod CIDR | "x.x.x.x/x" | "192.168.0.0/18" |
| NODE_HOSTNAME_FORMAT | Node hostname format. This is a format string that must contain exactly one %d format field that will be replaced with an integer representing the number of the node. | "node-%d" | "node-%d" |
| KUBERNETES_VERSION | Kubernetes version | "x.x.x" | "1.34.0" |
| UPGRADED_K8S_VERSION | Upgraded Kubernetes version | "x.x.x" | "1.34.0" |
| KUBERNETES_BINARIES_VERSION | Version of kubelet, kubeadm and kubectl | "x.x.x-xx" or "x.x.x" | same as KUBERNETES_VERSION |
| KUBERNETES_BINARIES_CONFIG_VERSION | Version of kubelet.service and 10-kubeadm.conf files | "vx.x.x" | "v0.13.0" |
| LIBVIRT_DOMAIN_TYPE | Which hypervisor to use for the virtual machines libvirt domain, default to kvm. It is possible to switch to qemu in case nested virtualization is not available, although it's considered experimental at this stage of development. | "kvm", "qemu" | "kvm" |
| NUM_NODES | Set the number of virtual machines to be provisioned. This VMs will be further configured as controlplane or worker Nodes. Note that CONTROL_PLANE_MACHINE_COUNT and WORKER_MACHINE_COUNT should sum to this value. | | 2 |
| FAKE_NODES_FILE | Path to save fake nodes generated in json file. | | "/opt/metal3-dev-env/fake_nodes.json" |
| CONTROL_PLANE_MACHINE_COUNT | Set the controlplane replica count in the target cluster. ||1|
| WORKER_MACHINE_COUNT | Set the worker replica count in the target cluster. ||1|
| VM_EXTRADISKS | Add extra disks to the virtual machines provisioned. By default the size of the extra disk is set in the libvirt Ansible role to 8 GB | "true", "false" | "false" |
| VM_EXTRADISKS_FILE_SYSTEM | Create file system to the extra disk. | "ext4", "xfs" | "ext4" |
| VM_EXTRADISKS_MOUNT_DIR | Mount the extra disk to a directory on a host. | | "/mnt/disk2" |
| VM_TPM_EMULATOR | Add TPM2.0 emulator to VMs. | "true", "false" | "false" |
| NODES_PLATFORM | Select the platform used to simulate the Baremetal hosts. | "libvirt", "fake" | "libvirt" |
| TARGET_NODE_MEMORY | Set the default memory size in MB for the virtual machines provisioned. | | 4096 |
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
| IRONIC_USE_MARIADB | Use MariaDB instead of SQLite. Setting this to "true" does not work with v0.2.0 and older versions of BMO. MariaDB cannot be used without TLS. | "true", "false" | "false" |
| REGISTRY_PORT | Container image registry port | | 5000 |
| HTTP_PORT | Httpd server port | | 6180 |
| IRONIC_INSPECTOR_PORT | Ironic Inspector port | | 5050 |
| IRONIC_API_PORT | Ironic Api port | | 6385 |
| RESTART_CONTAINER_CERTIFICATE_UPDATED | Enable the ironic restart feature when TLS certificates are updated | "true", "false" | "true" |
| NODE_DRAIN_TIMEOUT | Set the nodeDrainTimeoutSeconds for controlplane and worker template | | '0' |
| MARIADB_KEY_FILE | Path to the key of MariaDB | | /opt/metal3-dev-env/certs/mariadb.key |
| MARIADB_CERT_FILE | Path to the cert of MariaDB | | /opt/metal3-dev-env/certs/mariadb.crt |
| MARIADB_CAKEY_FILE | Path to the CA key of MariaDB | | /opt/metal3-dev-env/certs/ironic-ca.key |
| MARIADB_CACERT_FILE | Path to the CA certificate of MariaDB | | /opt/metal3-dev-env/certs/ironic-ca.pem |
| M3PATH | Path to clone the Metal3 Development Environment repository | | $HOME/go/src/github.com/metal3-io |
| BMOPATH | Path to clone the Bare Metal Operator repository | | $HOME/go/src/github.com/metal3-io/baremetal-operator |
| CAPM3PATH | Path to clone the Cluster API Provider Metal3 repository | | $HOME/go/src/github.com/metal3-io/cluster-api-provider-metal3 |
| CAPIPATH | Path to clone the Cluster API repository | | $HOME/go/src/github.com/metal3-io/cluster-api |
| IPAMPATH | Path to clone IP Address Manager repository | | $HOME/go/src/github.com/metal3-io/ip-address-manager |
| CAPIREPO | Cluster API git repository URL | | https://github.com/kubernetes-sigs/cluster-api |
| CAPIBRANCH | Cluster API git repository branch to checkout | | main |
| CAPICOMMIT | Cluster API git commit to checkout on CAPIBRANCH | | HEAD |
| BMOREPO | Baremetal Operator git repository URL | | https://github.com/metal3-io/baremetal-operator.git |
| BMOBRANCH | Baremetal Operator git repository branch to checkout | | main |
| BMOCOMMIT | BMO git commit to checkout on BMOBRANCH | | HEAD |
| CAPM3REPO | Cluster API Provider Metal3 git repository URL | | https://github.com/metal3-io/cluster-api-provider-metal3 |
| CAPM3BRANCH | Cluster API Provider Metal3 git repository branch to checkout | | main |
| CAPM3COMMIT | Cluster API Provider Metal3 git commit to checkout on CAPM3BRANCH | | HEAD |
| IPAMREPO | IP Address Manager git repository URL | | https://github.com/metal3-io/ip-address-manageri/ |
| IPAMBRANCH | IP Address Manager git repository branch to checkout | | main |
| IPAMCOMMIT | IP Address Manager git commit to checkout on IPAMBRANCH | | HEAD |
| IRONIC_IMAGE_PATH | Path to clone the Metal3's ironic-image Git repository to | | /tmp/ironic-image  |
| IRONIC_IMAGE_REPO | Metal3's ironic-image Git repository address | | https://github.com/metal3-io/ironic-image.git |
| IRONIC_IMAGE_BRANCH | Metal3's ironic-image Git repository branch | | main |
| IRONIC_IMAGE_COMMIT | Metal3's ironic-image | | HEAD |
| MARIADB_IMAGE_PATH | Path to clone the mariadb-image Git repository to | | /tmp/mariadb-image  |
| MARIADB_IMAGE_REPO | mariadb-image Git repository address | | https://github.com/metal3-io/mariadb-image.git |
| MARIADB_IMAGE_BRANCH | mariadb-mage branch to checkout | | main |
| MARIADB_IMAGE_COMMIT | mariadb-image commit to checkout | | HEAD |
| FORCE_REPO_UPDATE | discard existing directories | "true","false" | "true" |
| BUILD_CAPM3_LOCALLY | build Cluster API Provider Metal3 based on CAPM3PATH | "true","false" | "false" |
| BUILD_IPAM_LOCALLY | build IP Address Manager based on IPAMPATH | "true","false" | "false" |
| BUILD_BMO_LOCALLY | build Baremetal Operator based on BMOPATH | "true","false" | "false" |
| BUILD_CAPI_LOCALLY | build Cluster API based on CAPIPATH | "true","false" | "false" |
| BUILD_IRONIC_IMAGE_LOCALLY | build the Metal3's ironic-image based on IRONIC_IMAGE_PATH | "true","false" | "false" |
| BUILD_MARIADB_IMAGE_LOCALLY | build the MariaDB container image based on MARIADB_IMAGE_PATH | "true", "false" | "false" |
| IRONIC_FROM_SOURCE | installs ironic from source during container image building, if `true` then the `BUILD_IRONIC_IMAGE_LOCALLY` will be also set to `true` | "true","false" | "false" |
| IRONIC_SOURCE | absolute path of the ironic source code used to build the ironic services in the ironic container image | | |
| IRONIC_INSPECTOR_SOURCE | absolute path of the ironic-inspector source code used to build the ironic-inspector services in the ironic container image | | |
| SUSHY_SOURCE | absolute path of the sushy source code used to build the sushy library in the ironic container image | | |
| DHCP_HOSTS | A list of `;` separated dhcp-host directives for dnsmasq | e.g. `00:20:e0:3b:13:af;00:20:e0:3b:14:af` | |
| DHCP_IGNORE | A set of tags on hosts to be ignored by dnsmasq | e.g. `tag:!known` | |
| ENABLE_NATED_PROVISIONING_NETWORK | A single boolean to configure whether provisioner and provisioning networks are in separate subnets and there is NAT betweend them or not | "true","false" | "false" |
| CAPI_CONFIG_DIR | Cluster API config directory path  | `$HOME/.cluster-api/`, `$XDG_CONFIG_HOME/cluster-api`, `$HOME/.config/cluster-api` | `$HOME/.config/cluster-api` |
| IPA_BASEURI | IPA downloader will download IPA from this url | | https://tarballs.opendev.org/openstack/ironic-python-agent/dib |
| IPA_BRANCH | The last part of the name of the IPA archive | | master |
| IPA_FLAVOR | The middle part of the name of the IPA archive | | centos9 |
| IRSOREPO | Ironic Standalone Operator git repository URL | | https://github.com/metal3-io/ironic-standalone-operator.git |
| IRSOBRANCH | Ironic Standalone Operator git repository branch to checkout | | main |
| IRSOCOMMIT | Ironic Standalone Operator git commit to checkout on IRSOBRANCH | | HEAD |
<!-- markdownlint-enable MD013 MD034 -->

**NOTE** `(BMO/CAPI/CAPM3/IPAM)RELEASE` variables are also affecting the
`BRANCH` variables so make sure that RELEASE and BRANCH variables are
not conflicting.

## Local IPA

The use of local IPA enabled via `USE_LOCAL_IPA` is only supported on
Ubuntu host when `EPHEMERAL_CLUSTER` is `kind` cluster and Ironic is
directly deployed to  the OCI runtime (no K8s pod)

## Local images

Environment variables with `_LOCAL_IMAGE` in their name are used to
specify directories that contain the code to build the components
locally e.g. `CAPM3_LOCAL_IMAGE`.

## Additional networks

By default two libvirt networks are created `external` and `provisioning`
but in some circumstances it can be useful to define additional secondary
networks.

This can also be enabled via environment variables, the
`EXTRA_NETWORK_NAMES` variable defines a list of network names,
and then ipv4, ipv6 or dual stack subnets can be defined as in the
following example (note that the name prefix in the subnet variables
is always uppercase, even if the `EXTRA_NETWORK_NAMES` are lowercase):

```bash
export EXTRA_NETWORK_NAMES="nmstate1 nmstate2"
export NMSTATE1_NETWORK_SUBNET_V4='192.168.221.0/24'
export NMSTATE1_NETWORK_SUBNET_V6='fd2e:6f44:5dd8:ca56::/120'
export NMSTATE2_NETWORK_SUBNET_V4='192.168.222.0/24'
export NMSTATE2_NETWORK_SUBNET_V6='fd2e:6f44:5dd8:cc56::/120'
```

## Pinned binaries and packages

By default, we pin downloaded binaries and packages with SHA256 digests.
For testing purposes, verification of the digests will be skipped if
`INSECURE_SKIP_DOWNLOAD_VERIFICATION` is set to `true`.

## Make options

- `make` will run the installation of all te dependencies and set up the
   ephemeral controlplane
- `make nodep` will skip the dependency installation
- `make ci_run` will run only those make targets that are executed in the
   CI

## IPv6 support

The environment supports IPv6-only networking, but this currently works
**only with `kind`**. Minikube does not have official IPv6 support at the time
of writing. IPv6 can also be enabled partially, but for full IPv6
networking, the following additional steps are required:

1. Build iPXE image builder with IPv6 support and with correct name (or rename
   after building). By default the builder is named after the address it is
   hosted at. Also, by default it is enough if `IPXE_BUILDER_LOCAL_IMAGE`
   contains path to the folder with iPXE builder docker file, the dev env will
   build the buider automatically.
1. Build iPXE with IPv6 support. This is also done by the dev env with the
   correct vars and builder.
1. The Docker engine depends on containerd 1.7. To configure image registries
   using an IPv6 address, containerd version **2.0 or later** is required. You
   can download the correct containerd binary and replace the existing one under
   `/usr/local/bin`. There is a convenience script for this
   `hack/replace-containerd2.sh`. Notice that kind control plane contains
   containerd 2.x, so it should not be necessary to replace containerd on host.
1. You need to replace the default IPv4 addresses with IPv6 addresses in the
   environment variables.

Notice that if your host does not have support for native IPv6, you need to
enable NAT64 and DNS64 to provision the VMs. If you enable NAT64 with the
variable below, it will also enable DNS64.

The following variables need to be set:

``` sh
export IPXE_ENABLE_IPV6=true
export BUILD_IPXE=true
export IPXE_BUILDER_LOCAL_IMAGE="<path to local builder image>"
export EPHEMERAL_CLUSTER="kind"
export IP_STACK=v6
export EXTERNAL_SUBNET_V6="fd55::/64"
export BARE_METAL_PROVISIONER_SUBNET_IPV6_ONLY=true
export DOCKER_USE_IPV6_INTERNALLY=true
export POD_CIDR="fd00:6969::/64"
export ENABLE_NAT64=true # use if host does not support native IPv6
```
