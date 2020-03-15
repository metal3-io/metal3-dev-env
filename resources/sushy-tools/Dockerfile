FROM registry.hub.docker.com/library/python:3.7

RUN apt update && \
    apt install -y libvirt-dev && \
    pip3 install sushy-tools==0.8.0 libvirt-python

CMD sushy-emulator -i 0.0.0.0 -p 8000 --config /root/sushy/conf.py
