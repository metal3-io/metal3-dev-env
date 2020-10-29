#!/bin/bash

set -x 

PROCEDURE="${1}"

if [ "${PROCEDURE}" == "backup" ]; then
  BMH_LIST=$(kubectl get bmh -A | awk 'NR>1' | awk '{{print $2}}' | grep node)

  for bmh_node in ${BMH_LIST}; do
    bmh_node=$(echo "${bmh_node}" | sed -r 's/-/_/g')
    echo "Backup bmh node: ${bmh_node}"
    mkdir -p "${HOME}/backups"

    sudo virsh undefine "${bmh_node}"
    sudo virsh dumpxml --inactive --security-info "${bmh_node}" | sudo tee "${HOME}"/backups/"${bmh_node}"_backup.xml > /dev/null 2>&1
    sudo virsh blockcopy "${bmh_node}" sda "${HOME}"/backups/"${bmh_node}"_backup.qcow2 --wait --verbose --finish
    sudo virsh define --file "${HOME}"/backups/"${bmh_node}"_backup.xml
    sleep 10
    NOT_RUNNING_NODE_COUNT=$(sudo virsh list --all | awk 'NR>1' | grep -w "${bmh_node}" | awk '{{print $3}}' | grep -cv running)
    if [ "${NOT_RUNNING_NODE_COUNT}" -gt 0 ];then
      sudo virsh start "${bmh_node}"
    fi
  done
elif [ "${PROCEDURE}" == "restore" ]; then
  if [ -d "${HOME}/backups" ];then
    BMH_LIST=$(kubectl get bmh -A | awk 'NR>1' | awk '{{print $2}}' | grep node)

    for bmh_node in ${BMH_LIST}; do
      bmh_node=$(echo "${bmh_node}" | sed -r 's/-/_/g')
      echo "Restore bmh node: ${bmh_node}"

      sudo virsh undefine "${bmh_node}"
      sleep 10
      sudo rm /opt/metal3-dev-env/pool/"${bmh_node}".qcow2
      sudo rsync --progress "${HOME}"/backups/"${bmh_node}"_backup.qcow2 /opt/metal3-dev-env/pool/"${bmh_node}".qcow2
      sudo cp "${HOME}"/backups/"${bmh_node}"_backup.xml /opt/metal3-dev-env/pool/"${bmh_node}".xml
      sudo virsh define --file /opt/metal3-dev-env/pool/"${bmh_node}".xml
      sleep 10
      NOT_RUNNING_NODE_COUNT=$(sudo virsh list --all | awk 'NR>1' | grep -w "${bmh_node}" | awk '{{print $3}}' | grep -cv running)
      if [ "${NOT_RUNNING_NODE_COUNT}" -gt 0 ];then
        sudo virsh start "${bmh_node}"
      fi
    done
  else
    echo "Backup not found. Run './backup-restore-libvirt-vm.sh backup' first"
  fi
else
  echo "Script for backup and restore libvirt VMs"
  echo "Syntax: ./backup-restore-libvirt-vm.sh <backup|restore>"
  echo "Example: './backup-restore-libvirt-vm.sh backup'"
fi

