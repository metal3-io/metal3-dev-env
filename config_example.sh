#!/bin/bash

#
# Choose whether the "baremetal" libvirt network will use IPv4, IPv6, or IPv4+IPv6.
# This network is the primary network interface for the virtual bare metal hosts.
#
# Note that this only sets up the underlying network, and fully provisioning IPv6
# kubernetes clusters is not yet automated.  If IPv6 is enabled, DHCPv6 will
# be available to the virtual bare metal hosts.
#
# v4   -- IPv4 (default)
# v6   -- IPv6
# v4v6 -- dual-stack IPv4+IPv6
#
#export IP_STACK=v6

#
# This is the subnet used on the "baremetal" libvirt network, created as the
# primary network interface for the virtual bare metal hosts.
#
# V4 default of 192.168.111.0/24 set in lib/network.sh
# V6 default of fd55::/64 is set in lib/network.sh
#
#export EXTERNAL_SUBNET_V4="192.168.111.0/24"
#export EXTERNAL_SUBNET_V6="fd55::/64"

#
# This SSH key will be automatically injected into the provisioned host
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
# Set the Cluster Api Metal3 provider repository to clone
#
#export CAPM3REPO="${CAPM3REPO:-https://github.com/metal3-io/cluster-api-provider-metal3.git}"

#
# Set the Cluster Api Metal3 provider branch to checkout
#
#export CAPM3BRANCH="${CAPM3BRANCH:-master}"

#
# Force deletion of the BMO and CAPM3 repositories before cloning them again
#
#export FORCE_REPO_UPDATE="${FORCE_REPO_UPDATE:-false}"

#
# Run a local baremetal operator instead of deploying in Kubernetes
#
#export BMO_RUN_LOCAL=true

#
# Run a local CAPM3 operator instead of deploying in Kubernetes
#
#export CAPM3_RUN_LOCAL=true

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
# Set the driver. The default value is 'mixed' (alternate nodes between ipmi
# and redfish).
#
#export BMC_DRIVER="redfish"

# Select the Cluster API provider Metal3 version
# Accepted values : v1alpha3 v1alpha4
# default: v1alpha4
#
#export CAPM3_VERSION=v1alpha4

#export KUBERNETES_VERSION="v1.18.8"

# Version of kubelet, kubeadm and kubectl binaries
#export KUBERNETES_BINARIES_VERSION="${KUBERNETES_BINARIES_VERSION:-${KUBERNETES_VERSION}}"
#export KUBERNETES_BINARIES_CONFIG_VERSION="v0.2.7"

# Configure provisioning network for single-stack ipv6
#PROVISIONING_IPV6=false

# Image OS (can be "Cirros", "Ubuntu", "Centos", overriden by IMAGE_* if set)
#
#export IMAGE_OS="Cirros"

# Image for target hosts deployment
#
#export IMAGE_NAME="cirros-0.5.1-x86_64-disk.img"

# Location of the image to download
#
#export IMAGE_LOCATION="http://download.cirros-cloud.net/0.5.1"

# Image username for ssh
#
#export IMAGE_USERNAME="metal3"

# Container image for ironic pod
#
# export IRONIC_IMAGE="quay.io/metal3-io/ironic"

# Container image for vbmc container
#
#export VBMC_IMAGE="quay.io/metal3-io/vbmc"

# Container image for sushy-tools container
#
#export SUSHY_TOOLS_IMAGE="quay.io/metal3-io/sushy-tools"

# APIEndpoint IP for target cluster
#export CLUSTER_APIENDPOINT_IP="192.168.111.249"

# Cluster provisioning Interface
#export CLUSTER_PROVISIONING_INTERFACE="ironicendpoint"

# POD CIDR
# export POD_CIDR=${POD_CIDR:-"192.168.0.0/18"

# Node hostname format. This is a format string that must contain exactly one
# %d format field that will be replaced with an integer representing the number
# of the node.
# export NODE_HOSTNAME_FORMAT="node-%d"

# Ephemeral cluster used as management cluster for cluster API
# (can be "kind", "minikube" or "tilt"). Only "minikube" is supported with
# CentOS
# Selecting "tilt" does not deploy a management cluster, it is left up to the
# user
# export EPHEMERAL_CLUSTER=minikube

# Secure Ironic deployment with TLS ("true" or "false")
# export IRONIC_TLS_SETUP="true"

# Set nodeDrainTimeout for controlplane and worker template, otherwise default value will be  '0s'. 
#
#export NODE_DRAIN_TIMEOUT=${NODE_DRAIN_TIMEOUT:-"0s"}
