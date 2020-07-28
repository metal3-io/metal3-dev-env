M3PATH := "$(dirname "$(readlink -f "${0}")")/../../"
# This needs to be moved to upgrade.sh and different value should be set before
# each use case.
# export NUM_OF_MASTER_REPLICAS := 1
# export NUM_OF_WORKER_REPLICAS := 1

all: upgrade

.PHONY: upgrade
upgrade:
	bash upgrade.sh
