#!/bin/bash

SECRET_NAME_PREFIX=$1
OS_TYPE=${2:-unknown}

if [ -z "${SECRET_NAME_PREFIX}" ] || [ -z "${SSH_PUB_KEY}" ] ; then
    echo "Usage: user_data.sh <secret name prefix> [os type]"
    echo
    echo '    os type: "centos", or "unknown" (default)'
    echo
    echo 'Expected env vars:'
    echo '    SSH_PUB_KEY - path to ssh public key'
    exit 1
fi

#
# Our virtual bare metal environment is created with two networks: NIC 1)
# "provisioning" NIC 2) "baremetal"
#
# cloud-init based images will only bring up the first network interface by
# default.  We need it to bring up our second interface, as well.
#
# TODO(russellb) - It would be nice to make this more dynamic and also not
# platform specific.  cloud-init knows how to read a network_data.json file
# from config drive.  Maybe we could have the baremetal-operator automatically
# generate a network_data.json file that says to do DHCP on all interfaces that
# we know about from introspection.
#
network_config_files() {
if [ "$OS_TYPE" = "centos" ] ; then
cat << EOF
hostname: dev
users:
  - name: metal3
    groups: wheel
    sudo: ['ALL=(ALL) NOPASSWD:ALL']
    lock_passwd: false
    shell: /bin/bash
    ssh-authorized-keys:
      - <key>

yum_repos:
    kubernetes:
        baseurl: https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64
        enabled: 1
        gpgcheck: 1
        repo_gpgcheck: 1
        gpgkey: https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg

runcmd:
  - [ ifup, eth1 ]
  # Install updates
  - yum check-update
  # Install keepalived
  - yum install -y gcc kernel-headers kernel-devel
  - yum install -y keepalived
  - systemctl start keepalived
  - systemctl enable keepalived
  # Install docker
  - yum install -y yum-utils device-mapper-persistent-data lvm2
  - yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
  - yum install docker-ce docker-ce-cli containerd.io -y
  - usermod -aG docker metal3
  - systemctl start docker
  - systemctl enable docker
  # Install kubernetes
  - setenforce 0
  - sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config
  - yum install -y kubelet kubeadm kubectl --disableexcludes=kubernetes
  - systemctl enable --now kubelet
  - kubeadm init --apiserver-advertise-address 55.66.77.88 --ignore-preflight-errors=all 
  - mkdir -p /home/metal3/.kube
  - cp /etc/kubernetes/admin.conf /home/metal3/.kube/config
  - chown metal3:metal3 /home/metal3/.kube/config


# keepalived Configuration file
write_files:
  -  content: |
       ! Configuration File for keepalived
       
       global_defs {
          notification_email {
            sysadmin@mydomain.com
            support@mydomain.com
          }
          notification_email_from lb1@mydomain.com
          smtp_server localhost
          smtp_connect_timeout 30
       }
       
       vrrp_instance VI_1 {
           state MASTER
           interface eth0
           virtual_router_id 51
           priority 101
           advert_int 1
           authentication {
               auth_type PASS
               auth_pass 1111
           }
           virtual_ipaddress {
               55.66.77.88
           }
       }
     path: /etc/keepalived/keepalived.conf
  - path: /etc/sysconfig/network-scripts/ifcfg-eth1
    owner: root:root
    permissions: '0644'
    content: |
      BOOTPROTO=dhcp
      DEVICE=eth1
      ONBOOT=yes
      TYPE=Ethernet
      USERCTL=no
EOF
    fi
}

user_data_secret() {
    printf "#cloud-config\n\nssh_authorized_keys:\n  - " > .userdata.tmp
    cat ${SSH_PUB_KEY} >> .userdata.tmp
    printf "\n" >> .userdata.tmp
    network_config_files >> .userdata.tmp
cat << EOF
apiVersion: v1
data:
  userData: $(base64 -w 0 .userdata.tmp)
kind: Secret
metadata:
  name: ${SECRET_NAME_PREFIX}-user-data
  namespace: metal3
type: Opaque
EOF
rm .userdata.tmp
}

user_data_secret
