#!/bin/bash -x

name="$1"

status=$(vbmc show  -f value $name | grep status | cut -f2 -d' ')

export PATH=$PATH:/usr/local/bin

if [[ $status != "running" ]]; then
    vbmc start $name
fi
