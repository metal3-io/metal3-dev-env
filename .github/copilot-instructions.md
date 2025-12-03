# Metal3 Development Environment - AI Coding Assistant Instructions

## Project Overview

metal3-dev-env provides a complete development and testing environment
for the Metal3 stack. It automates the setup of a local Kubernetes
cluster with Ironic, BMO, CAPM3, and simulated bare metal hosts using
libvirt VMs. This is the primary environment for Metal3 development,
testing, and demonstrations.

## Architecture

### Components Deployed

1. **Management Cluster** - Kind or Minikube cluster running Metal3 controllers
2. **Ironic** - Deployed as containers or pods for bare metal provisioning
3. **Virtual BMCs** - VBMC (IPMI) or sushy-tools (Redfish) for VM management
4. **Libvirt VMs** - Simulated bare metal hosts (baremetal_0, baremetal_1, etc.)
5. **Networking** - Bridges for provisioning and external networks

### Network Architecture

```text
Host Machine
  ├── provisioning network (172.22.0.0/24)
  │   ├── Ironic services
  │   ├── Virtual BMCs
  │   └── VMs (for PXE boot)
  └── external network (192.168.111.0/24)
      └── VMs (for cluster traffic)
```

## Quick Start

```bash
# Clone repo
git clone https://github.com/metal3-io/metal3-dev-env.git
cd metal3-dev-env

# Basic setup with defaults (Ubuntu VMs, CAPM3 enabled)
make

# Centos VMs with specific Kubernetes version
export CAPI_VERSION=v1.7.0
export CAPM3_VERSION=v1.7.0
export IMAGE_OS=centos
make

# Cleanup
make clean
```

## Key Environment Variables

### Image and OS Configuration

- `IMAGE_OS` - OS for deployed VMs: `ubuntu`, `centos`, `opensuse`,
  `flatcar` (default: `ubuntu`)
- `KUBERNETES_VERSION` - K8s version for target cluster
  (default: `v1.30.0`)
- `NUM_NODES` - Number of worker VMs (default: `2`)
- `CONTROL_PLANE_MACHINE_COUNT` - Control plane VMs (default: `1`)

### Component Versions

- `CAPI_VERSION` - Cluster API version (default: `v1.7.4`)
- `CAPM3_VERSION` - CAPM3 version (default: `v1.7.0`)
- `BMO_VERSION` - BMO version (default: `main`)
- `IPAM_VERSION` - IPAM version (default: `v1.7.0`)

### Feature Flags

- `CAPM3_PATH` - Local path to CAPM3 repo (for development)
- `BAREMETAL_OPERATOR_PATH` - Local path to BMO repo
- `IPAM_PATH` - Local path to IPAM repo
- `BARE_METAL_PROVISIONER` - Provisioner type: `metal3` or `ironic`
  (default: `metal3`)
- `BMC_PROTOCOL` - BMC type: `ipmi`, `redfish`,
  `redfish-virtualmedia` (default: `redfish-virtualmedia`)
- `EPHEMERAL_CLUSTER` - Type: `kind`, `minikube`, `tilt`
  (default: `minikube`)

### Network Configuration

- `PROVISIONING_IP` - IP for Ironic services (default: `172.22.0.1`)
- `CLUSTER_PROVISIONING_IP` - IP for dhcp (default: `172.22.0.2`)
- `EXTERNAL_SUBNET_V4` - External network subnet
  (default: `192.168.111.0/24`)

## Development Workflows

### Testing Local Changes

**Test local BMO changes:**

```bash
export BAREMETAL_OPERATOR_PATH=/path/to/baremetal-operator
export FORCE_REPO_UPDATE=true
make
```

**Test local CAPM3 changes:**

```bash
export CAPM3_PATH=/path/to/cluster-api-provider-metal3
export FORCE_REPO_UPDATE=true
make
```

**Test specific feature:**

```bash
# Test pivoting
cd scripts/feature_tests/pivoting
./upgrade_management_cluster.sh

# Test remediation
cd scripts/feature_tests/remediation
./remediation_test.sh
```

### Common Make Targets

```bash
make                    # Full setup (downloads, creates cluster,
                        # deploys Metal3)
make clean              # Cleanup everything
make test               # Run deployment tests
make provision_cluster  # Deploy target cluster only
make deprovision        # Delete target cluster
make reprovision        # Delete and recreate target cluster
```

### Debugging

**Check VM status:**

```bash
sudo virsh list --all
sudo virsh console baremetal_0  # Access VM console
```

**Check BMC status:**

```bash
# For VBMC (IPMI)
vbmc list

# For sushy-tools (Redfish)
curl http://localhost:8000/redfish/v1/Systems/
```

**Check Ironic:**

```bash
export IRONIC_URL=http://172.22.0.1:6385
baremetal node list
baremetal node show <node-uuid>
```

**Check BareMetalHosts:**

```bash
kubectl get bmh -n metal3
kubectl get bmh -n metal3 <name> -o yaml
```

## Directory Structure

- `01_*.sh`, `02_*.sh`, etc. - Ordered setup scripts
- `scripts/` - Helper scripts and feature tests
- `lib/` - Shared bash functions
- `vm-setup/` - Libvirt VM definitions and setup
- `docs/` - Documentation and deployment workflows
- `Makefile` - Main entry point

## Script Execution Flow

1. `01_prepare_host.sh` - Install dependencies (libvirt, kubectl, etc.)
2. `02_configure_host.sh` - Setup networks, create VMs
3. `03_launch_mgmt_cluster.sh` - Create management cluster (kind/minikube)
4. `04_deploy_ironic.sh` - Deploy Ironic services
5. `05_deploy_bmh.sh` - Create BareMetalHost resources
6. `06_deploy_capi.sh` - Install CAPI providers
7. `07_deploy_cluster.sh` - Deploy target workload cluster

## Key Files Reference

- `Makefile` - Primary interface, calls scripts in order
- `scripts/environment.sh` - Sets all environment variables
- `lib/common.sh` - Shared functions
- `lib/images.sh` - Image download and preparation
- `lib/network.sh` - Network configuration
- `vm-setup/roles/` - Ansible roles for VM setup

## Common Pitfalls

1. **Port Conflicts** - Ironic, BMC services, and Kubernetes need
   specific ports available
2. **Libvirt Permissions** - User must be in libvirt group:
   `sudo usermod -aG libvirt $USER`
3. **Network Conflicts** - Provisioning/external networks must not
   conflict with existing networks
4. **Insufficient Resources** - Need enough RAM/CPU for management
   cluster + VMs (recommend 16GB+ RAM)
5. **Stale VMs** - Run `make clean` fully before recreating environment
6. **BMC Not Responding** - Check vbmc/sushy-tools logs, ensure VMs are
   properly defined
7. **Image Download Failures** - Check `CAPI_BASE_URL` and image
   availability

## Feature Testing

Located in `scripts/feature_tests/`:

- `pivoting/` - Test moving management components between clusters
- `remediation/` - Test machine remediation and replacement
- `upgrade/` - Test Kubernetes version upgrades
- `node_reuse/` - Test reusing nodes between clusters

Each test has a dedicated script that sets up the scenario and validates results.

## CI Integration

- Used by all Metal3 projects for integration testing
- Jenkins jobs use this for e2e tests
- GitHub Actions use this for workflow testing
- Supports multiple OS images and configurations

## Customization Examples

**Deploy with Tilt for iterative development:**

```bash
export EPHEMERAL_CLUSTER=tilt
make
# Controllers auto-reload on code changes
```

**Use local Ironic image:**

```bash
export IRONIC_IMAGE=localhost/my-ironic:latest
export IRONIC_IMAGE_PULL_POLICY=Never
make
```

**Test with IPv6:**

```bash
export IP_STACK=v6
export PROVISIONING_IPV6=true
make
```

**Deploy minimal setup (no CAPM3):**

```bash
export DEPLOY_CLUSTER_API=false
make
```

## Troubleshooting Commands

```bash
# Check all running VMs
sudo virsh list

# Check provisioning network
sudo virsh net-info baremetal

# Check BMO logs
kubectl logs -n baremetal-operator-system deploy/baremetal-operator-controller-manager

# Check CAPM3 logs
kubectl logs -n capm3-system deploy/capm3-controller-manager

# Check Ironic API
curl http://172.22.0.1:6385/v1/nodes | jq

# Delete stuck VM
sudo virsh destroy baremetal_0
sudo virsh undefine baremetal_0
```

## Version Compatibility

- Supports multiple CAPI/CAPM3 release versions
- Matrix tested with Ubuntu, CentOS, OpenSUSE
- Compatible with Kubernetes 1.28+
- Works with different BMC protocols (IPMI, Redfish)

## Advanced Configuration

**Custom cluster template:**

```bash
export CLUSTER_NAME=my-cluster
export CLUSTER_APIENDPOINT_HOST=192.168.111.249
export CLUSTER_APIENDPOINT_PORT=6443
make provision_cluster
```

**Multiple management clusters:**

```bash
# Use different cluster names and ports to avoid conflicts
export CLUSTER_NAME=cluster1
export API_ENDPOINT_PORT=6443
make
```

This environment is the foundation for all Metal3 development and
testing workflows. Understanding its structure and configuration options
is essential for effective Metal3 development.
