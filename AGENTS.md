# Metal3 Development Environment - AI Agent Instructions

Instructions for AI coding agents. For project overview, see [README.md](README.md).
For full environment variables list, see [vars.md](vars.md).

## Overview

Development and testing environment for the Metal3 stack. Sets up a local
Kubernetes cluster with Ironic, BMO, CAPM3, and simulated bare metal hosts
using libvirt VMs. Used for local development and as the foundation for
CI pipelines in all Metal3 projects.

**Warning:** Scripts are intrusive and reconfigure host networking/libvirt.
Must be run in a dedicated VM, not on a developer workstation.

**AI agents:** Do NOT run `make`, setup scripts, or host-modifying commands
unless explicitly confirmed by user that the environment is a dedicated
Metal3 dev VM. Lint scripts (`make lint`, `./hack/markdownlint.sh`) are
always safe.

## Repository Structure

| Directory | Purpose |
|-----------|---------|
| `lib/` | Shared bash functions (common.sh, network.sh, images.sh) |
| `tests/` | Ansible-based test framework and scripts |
| `vm-setup/` | Libvirt VM definitions (Ansible roles) |
| `hack/` | CI scripts (shellcheck, markdownlint) |

## Key Files

| File | Purpose |
|------|---------|
| `01_prepare_host.sh` | Install dependencies (libvirt, kubectl, etc.) |
| `02_configure_host.sh` | Setup networks, create VMs |
| `03_launch_mgmt_cluster.sh` | Create management cluster (kind/minikube) |
| `04_verify.sh` | Verify deployment |
| `Makefile` | Primary interface |

## Testing Standards

Run locally before PRs:

| Command | Purpose |
|---------|---------|
| `make` | Full setup (prepare, configure, launch, verify) |
| `make clean` | Cleanup everything |
| `make lint` | Run shellcheck |
| `./hack/markdownlint.sh` | Markdown linting |

## Key Environment Variables

Essential variables (see `vars.md` for complete list):

- `IMAGE_OS` - Target OS: `ubuntu`, `centos`, `flatcar` (default: `ubuntu`)
- `CAPM3_VERSION`, `CAPI_VERSION` - Component versions
- `EPHEMERAL_CLUSTER` - Cluster type: `kind`, `minikube`, `tilt`
- `BMC_DRIVER` - BMC protocol: `ipmi`, `redfish`, `redfish-virtualmedia`

**Testing local changes:**

- `CAPM3_PATH` - Local path to CAPM3 repo
- `BAREMETAL_OPERATOR_PATH` - Local path to BMO repo
- `IPAM_PATH` - Local path to IPAM repo

## Code Conventions

- **Shell**: Use `set -ex` in scripts
- Source `lib/common.sh` for shared functions

## CI Integration

This repo is the foundation for Metal3 CI:

- **CAPM3 E2E tests** run on top of metal3-dev-env
- **Jenkins pipelines** in
  [project-infra](https://github.com/metal3-io/project-infra) use this
- **Pre-built node images** from Nordix artifactory (`IMAGE_LOCATION`)

## Code Review Guidelines

When reviewing pull requests:

1. **Compatibility** - Changes must work across Ubuntu/CentOS/Flatcar
1. **CI impact** - Consider effects on CAPM3 e2e and Jenkins pipelines
1. **Idempotency** - Scripts should be re-runnable
1. **Cleanup** - `make clean` must fully reset state

Focus on: `lib/`, `0*_*.sh`, `tests/`, `vm-setup/`.

## AI Agent Guidelines

1. Read `vars.md` for environment variable documentation
1. Check `lib/common.sh` for existing helper functions
1. Run `make lint` before committing
1. Test changes with `make clean && make`

## Related Documentation

- [CAPM3 E2E Tests](https://github.com/metal3-io/cluster-api-provider-metal3/tree/main/test/e2e)
- [Project Infrastructure](https://github.com/metal3-io/project-infra)
- [Metal3 Book](https://book.metal3.io/developer_environment/tryit)
