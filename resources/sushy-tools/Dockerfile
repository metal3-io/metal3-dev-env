FROM registry.hub.docker.com/library/python:3.9

RUN apt update && \
    apt install -y libvirt-dev && \
    pip3 install sushy-tools==0.12.1 libvirt-python

CMD sushy-emulator -i :: -p 8000 --config /root/sushy/conf.py
