# Metal3 Development Environment (metal3-dev-env)

Shell and Ansible scripts that turn a Linux host into a full Metal3 test
bed: libvirt VMs as simulated bare metal hosts, BMC emulators, Ironic,
BMO, CAPM3 and IPAM on a kind or minikube management cluster. Project
overview: [README.md](README.md). Variables and defaults:
[vars.md](vars.md). Contribution rules: [CONTRIBUTING.md](CONTRIBUTING.md)
and the
[Metal3 community guide](https://github.com/metal3-io/community/blob/main/CONTRIBUTING.md).

This file holds only what you cannot cheaply infer from the code. Where it
disagrees with the code or the Makefile, trust those and report the
mismatch.

## AI-assisted contributions

Metal3 follows the CNCF and
[Linux Foundation generative AI policy](https://www.linuxfoundation.org/legal/generative-ai).

- AI is a tool. The human who opens a PR is its author and is responsible
  for every line of it, including licensing and third-party content.
- Review is a conversation between humans. A PR where an agent or bot
  answers reviewers will be closed. Agents may draft changes; the
  contributor reads them, understands them, and replies personally.

- Keep changes surgical. The smallest complete change that solves the
  stated problem wins. Every added file, function, flag, dependency or
  test helper must trace to that problem; anything that does not is
  bloat and gets removed. Prefer reusing existing code over new code.
  Report unrelated findings instead of fixing them in the same PR.

## Repository map

- `01_prepare_host.sh` .. `04_verify.sh`: setup stages, driven by the
  `Makefile`. `host_cleanup.sh` and `cluster_cleanup.sh` undo them.
- `lib/common.sh`: every default variable, sourced by all scripts.
  User overrides go in the gitignored `config_${USER}.sh`, created from
  `config_example.sh` on first run.
- `lib/download.sh`: checksum-verified binary downloads
  (`wget_and_verify`).
- `vm-setup/`: Ansible playbooks and roles for packages, libvirt, OVS,
  firewall and virtual BMCs.
- `tests/`: Ansible provision, pivot, repivot and deprovision tests
  (`make test`).

## Testing

- There are no unit tests. Local checks are `make lint` and the
  container-based `hack/*.sh` scripts, which honor `CONTAINER_RUNTIME`
  (default `podman`). CI jobs:
  [Prow](https://github.com/metal3-io/project-infra/blob/main/prow/config/jobs/metal3-io/metal3-dev-env.yaml)
  and `.github/workflows/`.
- Behavior is verified only by the Jenkins integration jobs
  (`metal3-dev-env-integration-test-{ubuntu,centos}-{main,release-*}`),
  which are optional and triggered on the PR with `/test <job>`.
- Conventions are whatever the existing scripts, roles and lint configs
  do. Read neighboring files before writing new ones.
- Before finishing, run `make lint` and the `hack/` checks for the file
  types you touched. All must pass. Name the integration jobs that cover
  the change in the PR description.
- Do not run `make` (other than `make lint`), any numbered or cleanup
  script, `tests/`, `vm-setup/` playbooks, or `hack/print_checksums.sh`
  unless the user confirms the host is a dedicated, disposable dev-env
  VM. Sourcing `lib/common.sh` alone runs `sudo`: it can add groups,
  creates and chowns `WORKING_DIR` (`/opt/metal3-dev-env`), and writes
  `config_${USER}.sh`. The stages install packages, reconfigure host
  networking, libvirt and firewall, and start containers and VMs.

## Invariants

These apply to writing and to reviewing changes.

- **Single branch, many releases.** Only `main` exists. Jenkins runs it
  for every supported CAPM3 release branch, selected by
  `CAPM3RELEASEBRANCH` in `lib/common.sh`, and also for IPA image
  builds. A change must keep every supported release branch working, not
  only `main`.
- **Variables.** Define each default in `lib/common.sh` (or the `lib/`
  file that owns it) with the `${VAR:-default}` form so users can
  override it, and document it in `vars.md`. Never change a default
  silently: CI jobs and users depend on them.
- **Host OS coverage.** Changes must work on every distro in
  `SUPPORTED_DISTROS` (`lib/common.sh`) and for each `IMAGE_OS`
  target listed in `vars.md`.
- **Re-runnable.** Every stage must be safe to re-run, and `make clean`
  must return the host to its pre-setup state.
- **Security.** Never weaken security to make something work: Ironic TLS
  (`IRONIC_TLS_SETUP`) and basic auth stay on by default, generated
  credentials stay out of the repository, and no secrets go in code,
  logs or committed config. Call out any change to authentication, TLS,
  firewall rules or exposed ports in the PR description.
- **Pinning.** Pin every tool and image version. Binary downloads go
  through `wget_and_verify` with a SHA256; `hack/print_checksums.sh`
  prints digests for pinned dependencies. Renovate bumps versions by
  regex (`renovate.json`), so keep the exact `VAR:-vX.Y.Z` form on the
  lines it matches in `lib/common.sh` and
  `vm-setup/roles/packages_installation/defaults/main.yml`. Pin GitHub
  Actions by commit SHA.

## External references

- [Metal3 Book, developer environment](https://book.metal3.io/developer_environment/tryit)
- [Metal3 design proposals](https://github.com/metal3-io/metal3-docs/tree/main/design)
