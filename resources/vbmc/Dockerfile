FROM docker.io/centos:centos8

RUN dnf install -y python3 python3-requests pkgconf-pkg-config python3-libvirt openssh-clients && \
    curl https://raw.githubusercontent.com/openstack/tripleo-repos/master/tripleo_repos/main.py | python3 - -b master current && \
    dnf update -y && \
    dnf clean all && \
    pip3 install virtualbmc && \
    rm -rf /var/cache/{yum,dnf}/*

CMD /usr/local/bin/vbmcd --foreground
