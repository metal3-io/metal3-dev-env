FROM docker.io/centos:centos8

RUN dnf install -y python3 python3-requests && \
    curl https://raw.githubusercontent.com/openstack/tripleo-repos/master/tripleo_repos/main.py | python3 - -b master current && \
    dnf update -y && \
    dnf install -y python3-virtualbmc && \
    dnf clean all && \
    rm -rf /var/cache/{yum,dnf}/*

CMD /usr/bin/vbmcd --foreground
