FROM docker.io/centos:centos8

RUN dnf install -y python3 python3-requests python3-pip && \
    curl https://raw.githubusercontent.com/openstack/tripleo-repos/master/tripleo_repos/main.py | python3 - -b master current && \
    dnf update -y && \
    dnf install -y python3-virtualbmc && \
    dnf clean all && \
    rm -rf /var/cache/{yum,dnf}/*

# NOTE(dtantsur): work around old pyghmi in RDO; this operation will become
# no-op once RDO is updated.
RUN pip3 install 'pyghmi>=1.5.13'

CMD /usr/bin/vbmcd --foreground
