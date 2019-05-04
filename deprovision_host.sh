#!/bin/bash

BMHOST=$1

if [ -z "${BMHOST}" ] ; then
    echo "Usage: provision_host.sh <BareMetalHost Name>"
    exit 1
fi

kubectl patch baremetalhost ${BMHOST} -n metal3 --type merge \
    -p '{"spec":{"image":{"url":"","checksum":""}}}'
