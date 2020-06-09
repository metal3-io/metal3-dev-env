M3PATH := "$(dirname "$(readlink -f "${0}")")/../../"
# This needs to be moved to upgrade.sh and different value should be set before
# each use case.
# NUM_OF_MASTER_REPLICAS := 1
# NUM_OF_WORKER_REPLICAS := 1

all: upgrade

.PHONY: upgrade
upgrade:
	# when merged use: 'wget -q https://raw.githubusercontent.com/Nordix/airship-dev-tools/master/upgrade_tests/upgrade.sh'
	wget -q https://raw.githubusercontent.com/Nordix/airship-dev-tools/02895b9eb66cff9e3cacb11ac6d7322e41a81562/upgrade_tests/upgrade.sh
	bash upgrade.sh
