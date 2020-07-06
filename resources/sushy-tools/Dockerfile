FROM registry.hub.docker.com/library/python:3.8

RUN apt update && \
    apt install -y libvirt-dev && \
    pip3 install git+https://opendev.org/openstack/sushy-tools.git@ff2be838b9da25998202a93f2120d1350f2a1f6e libvirt-python

CMD sushy-emulator -i :: -p 8000 --config /root/sushy/conf.py
