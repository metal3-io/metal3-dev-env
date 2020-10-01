FROM registry.hub.docker.com/library/python:3.8

RUN apt update && \
    apt install -y libvirt-dev && \
    pip3 install git+https://opendev.org/openstack/sushy-tools.git@5d1a1469558b0940d6351af29278c01598f8badf libvirt-python

CMD sushy-emulator -i :: -p 8000 --config /root/sushy/conf.py
