#!/bin/bash

set -x

M3PATH="$(dirname "$(readlink -f "${0}")")/../.."

pushd "${M3PATH}" || exit
make
