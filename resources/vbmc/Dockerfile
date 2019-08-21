FROM registry.hub.docker.com/library/python:3.7

RUN apt update && \
    apt install -y libvirt-dev && \
    pip3 install virtualbmc

CMD /usr/local/bin/vbmcd --foreground
