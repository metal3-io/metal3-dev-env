FROM registry.hub.docker.com/library/python:3.8

RUN apt update && \
    apt install -y libvirt-dev && \
    pip3 install git+https://opendev.org/openstack/sushy-tools.git@b3bbb5b108216e39e5d6a98ae34e3ec38b568cf5 libvirt-python

CMD sushy-emulator -i :: -p 8000 --config /root/sushy/conf.py
