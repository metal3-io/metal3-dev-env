#!/bin/bash

TEST=${TEST}

{METAL3_DIR}/scripts/run.sh

"${METAL3_DIR}"/scripts/fetch_manifests.sh