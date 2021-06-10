M3PATH := "$(dirname "$(readlink -f "${0}")")../../../"
export NUM_OF_MASTER_REPLICAS := 3
export NUM_OF_WORKER_REPLICAS := 1
export NUM_NODES := 4

all: fetch_manifests upgrade
fetch_manifests:
	./../../fetch_manifests.sh
upgrade:
	./upgrade.sh
