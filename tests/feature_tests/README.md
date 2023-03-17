# Feature tests framework

## Build Status

[![Ubuntu main feature test build status](https://jenkins.nordix.org/view/Metal3/job/metal3_main_feature_tests_ubuntu/badge/icon?subject=Feature-tests)](https://jenkins.nordix.org/view/Metal3/job/metal3_main_feature_tests_ubuntu/)
[![Centos main feature test build status](https://jenkins.nordix.org/view/Metal3/job/metal3_main_feature_tests_centos/badge/icon?subject=Feature-tests-centos)](https://jenkins.nordix.org/view/Metal3/job/metal3_main_feature_tests_centos/)

Feature tests framework is made to run a set of scripts for testing pivoting,
remediation, scale-in, node reuse functionalities of Metal3 project.
The framework relies on already existing test scripts of each
feature in Metal3-dev-env. The motivation behind the framework is to be able to
test inspection/remediation/healthcheck/pivoting/scale-in/node reuse/repivoting
features in Metal3-dev-env environment and detect breaking changes in advance.

Test-framework CI can be triggered from a pull request in CAPM3, BMO,
metal3-dev-env, project-infra, ironic-image, and
ironic-ipa-downloader repositories.
It is recommended to run test-framework CI especially when
introducing a commit related to
inspection/remediation/healthcheck/pivoting/scale-in/node reuse/repivoting
to ensure that new changes will not break the existing functionalities.

Test-framework can be triggered by leaving

- `/test-features-ubuntu` (Ubuntu based)
- `/test-features-centos` (Centos based)

comments for inspection/remediation/healthcheck/pivoting/scale-in/node reuse/repivoting.

The folder structure of the test-framework and its related scripts look
as following:

```ini
feature_tests/
├── cleanup_env.sh
├── feature_test_deprovisioning.sh
├── feature_test_provisioning.sh
├── feature_test_vars.sh
├── healthcheck
│   ├── healthcheck.sh
│   └── Makefile
├── inspection_test.sh
├── node_reuse
│   ├── Makefile
│   ├── node_reuse.sh
│   └── node_reuse_vars.sh
├── OWNERS
├── pivoting
│   ├── Makefile
│   ├── pivot.sh
│   └── repivot.sh
├── README.md
├── remediation
│   ├── Makefile
│   └── remediation.sh
└── setup_env.sh
```

Each feature has its own Makefile that will call feature specific test steps.
`setup_env.sh` is used to build an environment, i.e. run `make`, that will give
N (from the test-framework perspective N=4) number of ready BMH as an output.
`cleanup_env.sh` is used for intermediate cleaning between each feature test.
`feature_test_provisioning.sh` and `feature_test_deprovisioning.sh` are used by
each feature test to provision/deprovision cluster and BMH.

When the test-framework is triggered with `/test-features-ubuntu` or
`/test-features-centos`, it will:

- setup metal3-dev-env
   - run 01_\*, 02_\*, 03_\*, 04_\* scripts
- run remediation tests
   - provision cluster and BMH
   - run remediation tests
   - deprovision cluster and BMH
- run healthcheck tests
   - provision cluster and BMH
   - run healthcheck tests
   - deprovision cluster and BMH
- clean up the environment
   - run `cleanup_env.sh`
- run pivoting tests
   - provision cluster and BMH
   - run pivoting tests
- run scale-in and node reuse tests
   - run scale-in and node reuse tests for KubeadmControlPlane scenario
   - run node reuse tests for MachineDeployment scenario
- run repivoting tests
   - run repivoting tests
   - deprovision cluster and BMH
- clean up the environment
   - run `cleanup_env.sh`

## Environment variables

Currently the test-framework uses the following environment variables
by default for feature tests, in case of **Ubuntu** setup:

```bash
export IMAGE_OS=ubuntu
export EPHEMERAL_CLUSTER=kind
export CONTAINER_RUNTIME=docker
export NUM_NODES=4
```

while **Centos** uses:

```bash
export IMAGE_OS=centos
export EPHEMERAL_CLUSTER=minikube
export CONTAINER_RUNTIME=podman
export NUM_NODES=4
```

Both **Ubuntu** and **Centos** setups for feature tests use:

```bash
export CAPM3_VERSION=v1beta1
export CAPI_VERSION=v1beta1
```

Recommended resource requirements for the host machine are: 8C CPUs, 32 GB RAM,
300 GB disk space.

## CI jobs configuration

We are running two main jobs for the feature framework testing:
(in order as they are described below)

- inspection
- remediation
- healthcheck
- pivoting
- scale-in
- node reuse
- repivoting

The jobs are:
[main](https://jenkins.nordix.org/view/Metal3/job/metal3_main_feature_tests_ubuntu/)
job for Ubuntu and the other
[main](https://jenkins.nordix.org/view/Metal3/job/metal3_main_feature_tests_centos/)
job for Centos which runs every day.

Similarly two other jobs,
[Metal3_*_feature_tests_ubuntu](https://jenkins.nordix.org/view/Metal3/job/metal3_metal3_dev_env_feature_tests_ubuntu/)
and
[Metal3_*_feature_tests_centos](https://jenkins.nordix.org/view/Metal3/job/metal3_metal3_dev_env_feature_tests_centos/)
that can be run when triggered with `/test-features-ubuntu` and `/test-features-centos`
phrases for Ubuntu and Centos, accordingly on a pull request.

Depending on where from the job is triggered, **\*** can be:

- metal3_dev_env
- capm3
- bmo
- project_infra
- ironic_ipa_downloader
- ironic_image
- nordix_capm3
- nordix_metal3_dev_env
- nordix_bmo
