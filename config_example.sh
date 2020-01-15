#!/bin/bash

#
# This is the subnet used on the "baremetal" libvirt network, created as the
# primary network interface for the virtual bare metalhosts.
#
# Default of 192.168.111.0/24 set in lib/common.sh
#
#export EXTERNAL_SUBNET="192.168.111.0/24"

#
# This SSH key will be automatically injected into the provisioned host
# by the provision_host.sh script.
#
# Default of ~/.ssh/id_rsa.pub is set in lib/common.sh
#
#export SSH_PUB_KEY=~/.ssh/id_rsa.pub

#
# Select the Container Runtime, can be "podman" or "docker"
# Defaults to "podman"
#
#export CONTAINER_RUNTIME="podman"

#
# Set the Baremetal Operator repository to clone
#
#export BMOREPO="${BMOREPO:-https://github.com/metal3-io/baremetal-operator.git}"

#
# Set the Baremetal Operator branch to checkout
#
#export BMOBRANCH="${BMOBRANCH:-master}"

#
# Set the Cluster Api baremetal provider repository to clone
#
#export CAPBMREPO="${CAPBMREPO:-https://github.com/metal3-io/cluster-api-provider-baremetal.git}"

#
# Set the Cluster Api baremetal provider branch to checkout
#
#export CAPBMBRANCH="${CAPBMBRANCH:-master}"

#
# Force deletion of the BMO and CAPBM repositories before cloning them again
#
#export FORCE_REPO_UPDATE="${FORCE_REPO_UPDATE:-false}"

#
# Run a local baremetal operator instead of deploying in Kubernetes
#
#export BMO_RUN_LOCAL=true

#
# Run a local CAPI operator instead of deploying in Kubernetes
#
#export CAPBM_RUN_LOCAL=true

#
# Do not retry on failure during verifications or tests of the environment
# This should be true. It could only be set to false for verifications of a
# dev env deployment that fully completed. Otherwise failures will appear as
# resources are not ready.
#
#export SKIP_RETRIES=false

#
# Interval between retries after verification or test failure
#
#export TEST_TIME_INTERVAL=10

#
# Number of maximum verification or test retries
#
#export TEST_MAX_TIME=120

#
# Set the driver. The default value is 'ipmi'
#
#export BMC_DRIVER="redfish"

# Select the Cluster API version
# Accepted values : v1alpha1 v1alpha2
# default: v1alpha1
#
#export CAPI_VERSION=v1alpha1

# Configure provisioning network for single-stack ipv6
#PROVISIONING_IPV6=false

# Image OS (can be "Cirros", "Ubuntu", "Centos", overriden by IMAGE_* if set)
#
#export IMAGE_OS="Cirros"

# Image for target hosts deployment
#
#export IMAGE_NAME="cirros-0.4.0-x86_64-disk.img"

# Location of the image to download
#
#export IMAGE_LOCATION="http://download.cirros-cloud.net/0.4.0"

# Image username for ssh
#
#export IMAGE_USERNAME="cirros"

# Container image for ironic pod
#
# export IRONIC_IMAGE="quay.io/metal3-io/ironic"

# Container image for vbmc container
#
#export VBMC_IMAGE="quay.io/metal3-io/vbmc"

# Container image for sushy-tools container
#
#export SUSHY_TOOLS_IMAGE="quay.io/metal3-io/sushy-tools"
