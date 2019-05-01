#!/bin/bash -x

name="$1"

status=$(vbmc show  -f value $name | grep status | cut -f2 -d' ')

if [[ $status != "running" ]]; then
    vbmc start $name
fi
