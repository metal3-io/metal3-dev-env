FROM python:3.7

RUN apt update && \
    apt install -y libvirt-dev && \
    pip3 install git+https://opendev.org/openstack/sushy-tools.git \
        libvirt-python

CMD sushy-emulator -i 0.0.0.0 -p 8000 --config /root/sushy/conf.py
