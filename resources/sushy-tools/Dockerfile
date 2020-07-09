FROM registry.hub.docker.com/library/python:3.8

RUN apt update && \
    apt install -y libvirt-dev && \
    pip3 install sushy-tools==0.11.0 libvirt-python

CMD sushy-emulator -i :: -p 8000 --config /root/sushy/conf.py
