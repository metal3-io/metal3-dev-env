#!/bin/bash

METAL3_DIR="$(dirname "$(readlink -f "${0}")")/../.."
# shellcheck disable=SC1091
# shellcheck disable=SC1090
source "${METAL3_DIR}/lib/common.sh"

MACHINE_TYPE=$1
CONTROLPLANE_YAML=controlplane.yaml
WORKER_YAML=machinedeployment.yaml

SSH_PUB_KEY_CONTENT="$(cat "${SSH_PUB_KEY}")"
export SSH_PUB_KEY_CONTENT

# shellcheck disable=SC2016
PREKUBEADMCOMMANDS_UBUNTU='
    - ip link set dev enp2s0 up
    - dhclient enp2s0
    - mv /tmp/akeys /home/ubuntu/.ssh/authorized_keys
    - chown ubuntu:ubuntu /home/ubuntu/.ssh/authorized_keys
    - apt update -y
    - apt install net-tools -y
    - apt install -y gcc linux-headers-$(uname -r)
    - apt install -y keepalived
    - systemctl start keepalived
    - systemctl enable keepalived
    - apt install apt-transport-https ca-certificates curl gnupg-agent software-properties-common -y
    - curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
    - add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
    - apt update -y
    - apt install docker-ce docker-ce-cli containerd.io -y
    - usermod -aG docker ubuntu
    - curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
    - echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" > /etc/apt/sources.list.d/kubernetes.list
    - apt update
    - apt install -y kubelet kubeadm kubectl
    - systemctl enable --now kubelet'

# shellcheck disable=SC2016
PREKUBEADMCOMMANDS_MD_UBUNTU='
        - ip link set dev enp2s0 up
        - dhclient enp2s0
        - mv /tmp/akeys /home/ubuntu/.ssh/authorized_keys
        - chown ubuntu:ubuntu /home/ubuntu/.ssh/authorized_keys
        - apt update -y
        - apt install apt-transport-https ca-certificates curl gnupg-agent software-properties-common -y
        - curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
        - add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
        - apt update -y
        - apt install docker-ce docker-ce-cli containerd.io -y
        - usermod -aG docker ubuntu
        - curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
        - echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" > /etc/apt/sources.list.d/kubernetes.list
        - apt update
        - apt install -y kubelet kubeadm kubectl
        - systemctl enable --now kubelet'

# shellcheck disable=SC2089
POSTKUBEADMCOMMANDS="
    - mkdir -p /home/${IMAGE_USERNAME}/.kube
    - cp /etc/kubernetes/admin.conf /home/${IMAGE_USERNAME}/.kube/config
    - chown ${IMAGE_USERNAME}:${IMAGE_USERNAME} /home/${IMAGE_USERNAME}/.kube/config
    - kubectl --kubeconfig /home/${IMAGE_USERNAME}/.kube/config patch nodes {{ ds.meta_data.name }} --patch"' "{\"spec\":{\"providerID\":\"metal3://{{ ds.meta_data.uuid }}\"{{ '"'}}'"' }}"'

PREKUBEADMCOMMANDS_CENTOS="
    - ifup eth1
    - yum check-update
    - yum install -y gcc kernel-headers kernel-devel
    - yum update -y
    - yum install -y keepalived
    - systemctl start keepalived
    - systemctl enable keepalived
    - yum install -y yum-utils device-mapper-persistent-data lvm2
    - yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    - yum install docker-ce-18.09.9 docker-ce-cli-18.09.9 containerd.io -y
    - usermod -aG docker centos
    - systemctl start docker
    - systemctl enable docker
    - setenforce 0
    - sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config
    - yum install -y kubelet kubeadm kubectl --disableexcludes=kubernetes
    - systemctl enable --now kubelet"

PREKUBEADMCOMMANDS_MD_CENTOS="
        - ifup eth1
        - yum check-update
        - yum update -y
        - yum install -y yum-utils device-mapper-persistent-data lvm2
        - yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
        - yum install docker-ce-18.09.9 docker-ce-cli-18.09.9 containerd.io -y
        - usermod -aG docker centos
        - systemctl start docker
        - systemctl enable docker
        - setenforce 0
        - sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config
        - yum install -y kubelet kubeadm kubectl --disableexcludes=kubernetes
        - systemctl enable --now kubelet"

FILES_CENTOS="
    - path: /etc/keepalived/keepalived.conf
      content: |
        ! Configuration File for keepalived
        global_defs {
            notification_email {
            sysadmin@example.com
            support@example.com
            }
            notification_email_from lb@example.com
            smtp_server localhost
            smtp_connect_timeout 30
        }
        vrrp_instance VI_1 {
            state MASTER
            interface eth1
            virtual_router_id 1
            priority 101
            advert_int 1
            virtual_ipaddress {
                192.168.111.249
            }
        }
    - path: /etc/sysconfig/network-scripts/ifcfg-eth1
      owner: root:root
      permissions: '0644'
      content: |
        BOOTPROTO=dhcp
        DEVICE=eth1
        ONBOOT=yes
        TYPE=Ethernet
        USERCTL=no
    - path: /etc/yum.repos.d/kubernetes.repo
      owner: root:root
      permissions: '0644'
      content: |
        [kubernetes]
        name=Kubernetes
        baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64
        enabled=1
        gpgcheck=1
        repo_gpgcheck=0
        gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
    - path: /home/centos/.ssh/authorized_keys
      owner: centos:centos
      permissions: '0600'
      content: ${SSH_PUB_KEY_CONTENT}"

FILES_MD_CENTOS="
        - path: /etc/sysconfig/network-scripts/ifcfg-eth1
          owner: root:root
          permissions: '0644'
          content: |
            BOOTPROTO=dhcp
            DEVICE=eth1
            ONBOOT=yes
            TYPE=Ethernet
            USERCTL=no
        - path: /etc/yum.repos.d/kubernetes.repo
          owner: root:root
          permissions: '0644'
          content: |
            [kubernetes]
            name=Kubernetes
            baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64
            enabled=1
            gpgcheck=1
            repo_gpgcheck=0
            gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
        - path: /home/centos/.ssh/authorized_keys
          owner: centos:centos
          permissions: '0600'
          content: ${SSH_PUB_KEY_CONTENT}"

# shellcheck disable=SC2016
FILES_UBUNTU='
    - path: /etc/keepalived/keepalived.conf
      content: |
        ! Configuration File for keepalived
        global_defs {
            notification_email {
            sysadmin@example.com
            support@example.com
            }
            notification_email_from lb@example.com
            smtp_server localhost
            smtp_connect_timeout 30
        }
        vrrp_instance VI_1 {
            state MASTER
            interface enp2s0
            virtual_router_id 1
            priority 101
            advert_int 1
            virtual_ipaddress {
                192.168.111.249
            }
        }
    - path: /etc/network/interfaces
      owner: root:root
      permissions: '\"0644\"'
      content: |
        # interfaces(5) file used by ifup(8) and ifdown(8)
        auto lo
        iface lo inet loopback
        ## To configure a dynamic IP address
        auto enp2s0
        iface enp2s0 inet dhcp'"
    - path: /tmp/akeys
      owner: root:root
      permissions: \"0644\"
      content: ${SSH_PUB_KEY_CONTENT}"

# shellcheck disable=SC2016
FILES_MD_UBUNTU='
        - path: /etc/network/interfaces
          owner: root:root
          permissions: '\"0644\"'
          content: |
            # interfaces(5) file used by ifup(8) and ifdown(8)
            auto lo
            iface lo inet loopback
            ## To configure a dynamic IP address
            auto enp2s0
            iface enp2s0 inet dhcp'"
        - path: /tmp/akeys
          owner: root:root
          permissions: \"0644\"
          content: ${SSH_PUB_KEY_CONTENT}"

if [ -z "$MACHINE_TYPE" ]; then
    echo "Usage: create_machine.sh <machine_type>"
    exit 1
fi

make_machine() {

    if [ "${IMAGE_OS}" == Ubuntu ]; then
        export PREKUBEADMCOMMANDS="${PREKUBEADMCOMMANDS_UBUNTU}"
        export WRITE_FILES="${FILES_UBUNTU}"
        export PREKUBEADMCOMMANDS_MD="${PREKUBEADMCOMMANDS_MD_UBUNTU}"
        export WRITE_FILES_MD="${FILES_MD_UBUNTU}"
        # shellcheck disable=SC2090
        export POSTKUBEADMCOMMANDS
    else
        export PREKUBEADMCOMMANDS="${PREKUBEADMCOMMANDS_CENTOS}"
        export WRITE_FILES="${FILES_CENTOS}"
        export PREKUBEADMCOMMANDS_MD="${PREKUBEADMCOMMANDS_MD_CENTOS}"
        export WRITE_FILES_MD="${FILES_MD_CENTOS}"
        # shellcheck disable=SC2090
        export POSTKUBEADMCOMMANDS
    fi
    if [ "${MACHINE_TYPE}" == controlplane ]; then
        envsubst < "${V1ALPHA2_CR_PATH}${CONTROLPLANE_YAML}"
    fi
    if [ "${MACHINE_TYPE}" == worker ]; then
        envsubst < "${V1ALPHA2_CR_PATH}${WORKER_YAML}"
    fi

}

make_machine | kubectl apply -n metal3 -f -
