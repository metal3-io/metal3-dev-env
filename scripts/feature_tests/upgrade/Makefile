M3PATH := "$(dirname "$(readlink -f "${0}")")/../../"
# This needs to be moved to upgrade.sh and different value should be set before
# each use case.
# NUM_OF_MASTER_REPLICAS := 1
# NUM_OF_WORKER_REPLICAS := 1

all: upgrade

.PHONY: upgrade
upgrade:
	wget -q https://raw.githubusercontent.com/Nordix/airship-dev-tools/master/upgrade_tests/upgrade.sh
	bash upgrade.sh
