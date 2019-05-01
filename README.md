Metal³ Development Environment
==============================

This repository includes scripts to set up a Metal³ development environment.

Prerequisites:
 * System with CentOS 7
 * Bare metal preferred, as we will be creating VMs to emulate bare metal hosts
 * run as a user with passwordless sudo access

# Instructions

tl;dr - Run `make`.

The `Makefile` runs a series of scripts, described here:

* `01_install_requirements.sh` - Installs all needed packages.

* `02_configure_host.sh` - Create a set of VMs that will be managed as if they
  were bare metal hosts.
