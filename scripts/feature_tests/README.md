# Feature tests framework

## Build Status

[![Ubuntu V1alpha3 build status](https://jenkins.nordix.org/view/Airship/job/airship_master_feature_tests_ubuntu/badge/icon?subject=Feature-tests)](https://jenkins.nordix.org/view/Airship/job/airship_master_feature_tests_ubuntu/)

Feature tests framework is made to run a set of scripts for testing pivoting,
remediation and upgrade functionalities of Metal3 project.
The framework relies on already existing test scripts of each
feature in Metal3-dev-env. The motivation behind the framework is to be able to
test pivoting/remediation/upgrade features in Metal3-dev-env environment and
detect breaking changes in advance.

Test-framework CI can be triggered from a pull request in CAPM3, BMO,
metal3-dev-env, project-infra, ironic-image, ironic-inspector-image and
ironic-ipa-downloader repositories.
It is recommended to run test-framework CI especially when
introducing a commit related to pivoting/remediation/upgrade, to ensure that new
changes will not break the existing functionalities.

Test-framework can be triggered by leaving `/test-features` comment on a pull
request. The folder structure of the test-framework and its related scripts
look as following:

```ini
├── feature_tests
│   ├── cleanup_env.sh
│   ├── feature_test_deprovisioning.sh
│   ├── feature_test_provisioning.sh
│   ├── pivoting
│   │   └── Makefile
│   ├── remediation
│   │   └── Makefile
│   ├── setup_env.sh
│   └── upgrade
│       └── Makefile
```

Each feature has its own Makefile that will call feature specific test steps.
`setup_env.sh` is used to build an environment, i.e. run `make`, that will give
N (from the test-framework perspective N=4) number of ready BMH as an output.
`cleanup_env.sh` is used for intermediate cleaning between each feature test.
`feature_test_provisioning.sh` and `feature_test_deprovisioning.sh` are used by
each feature test to provision/deprovision cluster and BMH.

When the test-framework is triggered, it will:

- setup metal3-dev-env
  - run 01_\*, 02_\*, 03_\*, 04_\* scripts
- run remediation tests
  - provision cluster and BMH
  - run remediation tests
  - deprovision cluster and BMH
- clean up the environment
  - run `cleanup_env.sh`
- run upgrade tests
  - provision cluster and BMH
  - run remediation tests
  - deprovision cluster and BMH
- clean up the environment
  - run `cleanup_env.sh`
- run pivoting tests
  - provision cluster and BMH
  - run remediation tests
  - deprovision cluster and BMH
  - destroy the environment (i.e. run `make clean`)

## Environment variables

Currently the test-framework uses the following environment variables
by default:

```bash
export CAPM3_VERSION=v1alpha4
export IMAGE_OS=Ubuntu
export EPHEMERAL_CLUSTER=kind
export CONTAINER_RUNTIME=docker
export NUM_NODES=4
```

Environment variables needed for upgrade tests running clusterctl,
set as default values:

```bash
export CAPM3RELEASE=v0.3.2
export CAPIRELEASE=v0.3.4
```

Recommended resource requirements for the host machine: 8C CPUs, 32 GB RAM, 300
GB disk space.

## CI jobs configuration

We are running two jobs for the framework testing. One is
[master](https://jenkins.nordix.org/view/Airship/job/airship_master_feature_tests_ubuntu/)
job which runs every day, and second one is
[airship_*_feature_tests_ubuntu](https://jenkins.nordix.org/view/Airship/job/airship_metal3io_metal3_dev_env_feature_tests_ubuntu/)
that can be triggered with `/test-features` phrase on a pull request. Depending
on where from the job
is triggered, **\*** can be:

- metal3io_metal3_dev_env
- metal3io_capi_m3
- metal3io_bmo
- metal3io_project_infra
- metal3io_ironic_ipa_downloader
- metal3io_ironic_inspector
- metal3io_ironic_image
- nordix_capi_m3
- nordix_metal3_dev_env
- nordix_bmo
