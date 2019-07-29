#!/usr/bin/env bash
OS=$(awk -F= '/^ID=/ { print $2 }' /etc/os-release | tr -d '"')
if [[ $OS == ubuntu ]]; then
  source ubuntu_install_requirements.sh
else
  source centos_install_requirements.sh
fi
