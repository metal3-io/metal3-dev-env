# Local Development Setup for Metal3

A simple guide to running Metal3 components locally using Tilt. The Tiltfile.
It is possible to use Tilt to run the CAPI, BMO, CAPM3 and IPAM components.

If you are running tilt on a remote machine, you can forward the web interface
by adding the following parameter to the ssh command `-L 10350:127.0.0.1:10350`

Then you can access the Tilt dashboard locally [here](http://127.0.0.1:10350)

*Note*: It is easiest if you configure all these in `config_<username>.sh` file,
which is automatically sourced if it exists.

The Tiltfile installs four Metal3 components in this order:

1. **IRSO** - Ironic Standalone Operator
2. **BMO** - Baremetal Operator  
3. **IPAM** - IP Address Manager
4. **CAPM3** - Cluster API Provider Metal3

## Prerequisites

Install these tools before running tilt up:

- A Kubernetes cluster with context `kubernetes-admin@kubernetes`
- Docker
- kubectl
- clusterctl
- kustomize
- envsubst

## Quick Start

### 1. Start the environment

```bash
tilt up
```

This will:

- Check that all required tools are installed
- Clone repositories to `./local-dev` (only if they don't exist)
- Deploy cert-manager (by default v1.19.1)
- Initialize Cluster API with kubeadm bootstrap and control-plane providers
    (by default v1.11.3)
- Build Docker images for all Metal3 components using ttl.sh registry
- Deploy components with resource dependencies (IRSO → BMO → IPAM → CAPM3)

### 2. Tear down the environment

```bash
tilt down
```

This will remove all deployed resources in reverse dependency order.

### 3. Tear down with repository cleanup

```bash
tilt down -- --prune=true
# or
tilt down -- --prune
```

This will remove all deployed resources AND delete the `./local-dev`
directory with cloned repositories.

## Customization

Customize deployment parameters using environment variables:

### Repository Sources

```bash
# Choose ONE of the following formats:

# Format 1: Repository name only (falls back to default org - metal3-io)
export CAPM3_REMOTE="cluster-api-provider-metal3"
# Format 2: org/repo
export CAPM3_REMOTE="yourorg/cluster-api-provider-metal3"
# Format 3: Full URL without .git
export CAPM3_REMOTE="https://github.com/yourorg/cluster-api-provider-metal3"
# Format 4: Full URL with .git
export CAPM3_REMOTE="https://github.com/yourorg/cluster-api-provider-metal3.git"

# Available for all components:
export CAPM3_REMOTE="yourorg/cluster-api-provider-metal3"
export BMO_REMOTE="yourorg/baremetal-operator"
export IPAM_REMOTE="yourorg/metal3-ipam"
export IRSO_REMOTE="yourorg/ironic-standalone-operator"
```

### Branch Selection

```bash
# Specify branches for each component (defaults to 'main')
export CAPM3_BRANCH="your-feature-branch"
export BMO_BRANCH="your-feature-branch"
export IPAM_BRANCH="your-feature-branch"
export IRSO_BRANCH="your-feature-branch"
```

### Versions

```bash
export CAPI_VERSION="v1.11.3"           # Cluster API version
export CERT_MANAGER_VERSION="v1.19.1"    # cert-manager version
```

### Local Development Directory

```bash
export LOCAL_DEV_DIR="./my-custom-dir"  # Default: ./local-dev
```

### Component Providers

```bash
export CAPI_BOOTSTRAP_PROVIDER="kubeadm"       # Bootstrap provider
export CAPI_CONTROLPLANE_PROVIDER="kubeadm"    # Control plane provider
export CAPI_CORE_PROVIDER="cluster-api"        # Core provider
```

## File Structure

```text
./local-dev/
├── baremetal-operator/
├── cluster-api-provider-metal3/
├── ip-address-manager/
└── ironic-standalone-operator/
```
